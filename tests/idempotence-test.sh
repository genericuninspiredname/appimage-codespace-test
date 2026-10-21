#!/usr/bin/env bash
# Idempotence + lifecycle test for .devcontainer/setup.sh
# (foundation/merge-safe-layout).
#
# Phase 1 runs the REAL coordinator four times against an isolated
# fixture:
#   run 1: first-start   (as postCreate does)
#   run 2: normal-start  (as postStart does)
#   run 3: first-start   (a rebuild re-fires postCreate; hooks must NOT
#                         run again because the marker exists)
#   run 4: no argument   (manual run; mode inferred from the marker)
#
# After run 1 the observable state (persistent data dir, fake home,
# installed tool scripts, fluxbox config, symlinks) is snapshotted; later
# runs must leave it byte-identical, and managed blocks must appear
# exactly once.
#
# Phase 2 verifies hook-failure semantics: a failing first-start hook
# warns, lets later hooks run, does not write the completion marker, and
# is retried on the next run.
#
# The fixture stubs commands that need the built image or a real root
# system (useradd/chown/xhost, id for the roblox user) and isolates git's
# global config via GIT_CONFIG_GLOBAL. When user namespaces are available
# the run happens inside a private user+mount namespace (tmpfs over /run
# and /home) so nothing outside the temp dir is touched; when they are
# not (e.g. Codespaces, which blocks unshare) and we are root, the run
# happens directly - its side effects are the same paths the real setup
# manages (/home/roblox link, /run/user/<uid>) and self-heal on the next
# real setup run.
set -e

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
WORK=$(mktemp -d /tmp/setup-idem.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- fixture: fake origin repo (fetch of desktop-data must fail fast) --------
git init -q --bare "$WORK/origin.git"

# --- fixture: stubs -----------------------------------------------------------
mkdir -p "$WORK/stub"
for cmd in useradd chown xhost; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/stub-%s.log"\nexit 0\n' "$cmd" "$WORK" "$cmd" \
    > "$WORK/stub/$cmd"
  chmod +x "$WORK/stub/$cmd"
done
# id: answer for the roblox user, pass everything else through
cat > "$WORK/stub/id" <<'EOF'
#!/bin/sh
case " $* " in *" roblox"*|*"roblox "*) echo 4242; exit 0;; esac
exec /usr/bin/id "$@"
EOF
chmod +x "$WORK/stub/id"

# --- fixture: a copy of .devcontainer + repo (setup resolves modules
# relatively; the repo copy keeps wallpaper copying exercisable even when
# the real repo path sits under a tmpfs-mounted /home) --------------------------
cp -r "$REPO/.devcontainer" "$WORK/dc"
cp -r "$REPO" "$WORK/repo-src"
rm -rf "$WORK/repo-src/.git"
REPO_SRC="$WORK/repo-src"

# --- fixture: test hooks (proof the hook dirs are live) ----------------------
printf '#!/bin/sh\necho first >> "%s/hook-first.log"\n' "$WORK" > "$WORK/dc/hooks/first-start.d/90-test.sh"
printf '#!/bin/sh\necho normal >> "%s/hook-normal.log"\n' "$WORK" > "$WORK/dc/hooks/normal-start.d/90-test.sh"
chmod +x "$WORK/dc/hooks/first-start.d/90-test.sh" "$WORK/dc/hooks/normal-start.d/90-test.sh"

# --- fixture: a home that looks "used" -----------------------------------------
H="$WORK/home"
mkdir -p "$H/.fluxbox" "$H/Files/docs" "$H/.mozilla/firefox/abc123.default-release" \
         "$H/.var/app/org.vinegarhq.Sober" "$H/.cache"
echo "hello" > "$H/Files/docs/note.txt"
cat > "$H/.fluxbox/menu" <<'EOF'
[begin] (Fluxbox)
[exec] (Old App) {oldapp}
[end]
EOF
printf 'session.screen0.workspaces: 2\n' > "$H/.fluxbox/init"
printf 'user_pref("webgl.disabled", true);\nuser_pref("user.set", 1);\n' \
  > "$H/.mozilla/firefox/abc123.default-release/user.js"
echo x > "$H/.var/app/org.vinegarhq.Sober/state.json"
printf 'Old User Line\n' > "$H/.fluxbox/keys"

mkdir -p "$WORK/data" "$WORK/bin" "$WORK/xwww-dir"

# --- run helper: real coordinator, isolated env --------------------------------
ISOLATED=0
if unshare -rm true 2>/dev/null; then ISOLATED=1; fi

run_setup() { # run_setup <fixture-root> <mode>  ("" mode = no argument)
  local fx="$1" mode="$2" inner
  inner='
    set -e
    cd "'"$fx"'/home"   # git needs a valid cwd (the tmpfs mounts can hide it)
    export HOME="'"$fx"'/home"
    export PATH="'"$WORK"'/stub:$PATH"
    export GIT_CONFIG_GLOBAL="'"$WORK"'/gitconfig"
    export DESKTOP_HOME="'"$fx"'/home"
    export DESKTOP_DATA_DIR="'"$fx"'/data"
    export DESKTOP_BIN_DIR="'"$fx"'/bin"
    export DESKTOP_XWWW="'"$fx"'/xwww-dir/x-www-browser"
    export DESKTOP_REPO_DIR="'"$REPO_SRC"'"
    export DESKTOP_REMOTE_URL="file://'"$WORK"'/origin.git"
    bash "'"$WORK"'/dc/setup.sh" '"${mode:+$mode}"'
  '
  if [ "$ISOLATED" = 1 ]; then
    unshare -rm bash -c 'mount -t tmpfs tmpfs /run; mount -t tmpfs tmpfs /home; '"$inner"
  else
    [ "$(id -u)" = 0 ] || fail "not root and no user namespaces - cannot isolate"
    bash -c "$inner"
  fi
}

# --- snapshot observable state --------------------------------------------------
snapshot() { # snapshot > file
  {
    ( cd "$WORK/data"  && find . -path ./.git -prune -o -print \
        | LC_ALL=C sort | while read -r p; do
          if [ -L "$p" ]; then echo "L $p -> $(readlink "$p")"
          elif [ -f "$p" ]; then echo "F $p $(md5sum < "$p" | cut -d" " -f1)"
          else echo "D $p"; fi; done )
    ( cd "$H"         && find . -name .cache -prune -o -print \
        | LC_ALL=C sort | while read -r p; do
          if [ -L "$p" ]; then echo "L $p -> $(readlink "$p")"
          elif [ -f "$p" ]; then echo "F $p $(md5sum < "$p" | cut -d" " -f1)"
          else echo "D $p"; fi; done )
    ( cd "$WORK/bin"  && find . -type f -print | LC_ALL=C sort | while read -r p; do
          echo "B $p $(md5sum < "$p" | cut -d" " -f1)"; done )
    md5sum < "$WORK/xwww-dir/x-www-browser" | sed 's/^/X /'
  }
}

echo "== run 1: first-start"
run_setup "$WORK" first-start || fail "first-start run exited non-zero"
[ -f "$WORK/data/.first-start-complete" ] || fail "first-start marker missing"
[ -f "$WORK/hook-first.log" ] || fail "first-start hook did not run"
[ ! -f "$WORK/hook-normal.log" ] || fail "normal-start hook ran on first start"
snapshot > "$WORK/snap1"

echo "== run 2: normal-start"
run_setup "$WORK" normal-start || fail "normal-start run exited non-zero"
[ -f "$WORK/hook-normal.log" ] || fail "normal-start hook did not run"
[ "$(wc -l < "$WORK/hook-first.log")" = 1 ] || fail "first-start hook ran on normal start"
snapshot > "$WORK/snap2"
diff "$WORK/snap1" "$WORK/snap2" > /dev/null \
  || fail "state changed between first-start and normal-start"

echo "== run 3: repeated first-start (rebuild re-fires postCreate)"
run_setup "$WORK" first-start || fail "repeated first-start run exited non-zero"
[ "$(wc -l < "$WORK/hook-first.log")" = 1 ] \
  || fail "first-start hooks re-ran although the marker exists"
snapshot > "$WORK/snap3"
diff "$WORK/snap1" "$WORK/snap3" > /dev/null \
  || fail "state changed on repeated first-start"

echo "== run 4: no argument (manual run, mode inferred)"
run_setup "$WORK" "" || fail "no-arg run exited non-zero"
snapshot > "$WORK/snap4"
diff "$WORK/snap1" "$WORK/snap4" > /dev/null \
  || fail "state changed on no-arg run"

# --- behavior assertions ---------------------------------------------------------
MENU="$WORK/data/private/fluxbox/menu"
grep -c '^# >>> desktop-apps >>>' "$MENU" | grep -qx 1 || fail "menu managed block not exactly once"
grep -q '\[exec\] (Old App)' "$MENU" || fail "user menu entries lost"
grep -q 'Old User Line' "$WORK/data/private/fluxbox/keys" || fail "user keys lost"
grep -c '^# >>> desktop-keys >>>' "$WORK/data/private/fluxbox/keys" | grep -qx 1 || fail "keys block not exactly once"
grep -c '^# >>> desktop-init >>>' "$WORK/data/private/fluxbox/init" | grep -qx 1 || fail "init block not exactly once"
grep -c '^# >>> desktop-overlay >>>' "$WORK/data/private/fluxbox/overlay" | grep -qx 1 || fail "overlay block not exactly once"
grep -qx 'session.screen0.workspaces: 4' "$WORK/data/private/fluxbox/init" || fail "init values not applied"
[ -L "$H/Files" ] && [ "$(readlink "$H/Files")" = "$WORK/data/files" ] || fail "~/Files not linked to data dir"
[ -L "$H/.mozilla" ] || fail "~/.mozilla not linked"
[ -L "$H/.fluxbox" ] && [ "$(readlink "$H/.fluxbox")" = "$WORK/data/private/fluxbox" ] || fail "~/.fluxbox not linked"
ls "$WORK"/data/files/Imported-from-home-*/docs/note.txt >/dev/null 2>&1 \
  || fail "home Files not imported into data dir"
[ -x "$WORK/bin/desktop-backup" ] || fail "desktop-backup not installed"
[ -x "$WORK/bin/desktop-profile" ] || fail "desktop-profile not installed"
[ -x "$WORK/xwww-dir/x-www-browser" ] || fail "browser launcher not installed"
grep -q 'webgl.force-enabled", true' "$H/.mozilla/firefox/abc123.default-release/user.js" || fail "webgl pref missing"
[ "$(grep -c 'webgl' "$H/.mozilla/firefox/abc123.default-release/user.js")" = 2 ] || fail "webgl prefs duplicated"
grep -q 'user.set' "$H/.mozilla/firefox/abc123.default-release/user.js" || fail "user-authored prefs lost"
[ -f "$H/.cache/.disable-namespaces-check" ] || fail "namespaces-check flag missing"
[ -f "$WORK/data/.gitignore" ] || fail "data-dir gitignore missing"
[ -d "$WORK/data/.git" ] || fail "data dir not a git repo"
git -C "$WORK/data" remote get-url origin | grep -q origin.git || fail "data dir remote wrong"
[ -f "$WORK/data/private/fluxbox/backgrounds/wallpaper.png" ] || fail "wallpaper not copied"
# git safe.directory: guarded add -> exactly one entry per path after 4 runs
[ "$(grep -c "directory = $REPO_SRC" "$WORK/gitconfig")" = 1 ] \
  || fail "safe.directory repo entry not exactly once"
[ "$(grep -c 'directory = /workspaces/appimage-codespace-test' "$WORK/gitconfig")" = 1 ] \
  || fail "safe.directory fixed entry not exactly once"

# --- phase 2: hook-failure semantics --------------------------------------------
echo "== phase 2: failing first-start hook"
mkdir -p "$WORK/fx2/home" "$WORK/fx2/data" "$WORK/fx2/bin" "$WORK/fx2/xwww-dir"
cat > "$WORK/dc/hooks/first-start.d/05-failing.sh" <<EOF
#!/bin/sh
echo fail >> "$WORK/hook-fail.log"
exit 1
EOF
cat > "$WORK/dc/hooks/first-start.d/95-after-failure.sh" <<EOF
#!/bin/sh
echo after >> "$WORK/hook-after-fail.log"
EOF
chmod +x "$WORK/dc/hooks/first-start.d/05-failing.sh" "$WORK/dc/hooks/first-start.d/95-after-failure.sh"
OUT=$(run_setup "$WORK/fx2" first-start 2>&1) || true
# reuse run_setup machinery with the second fixture
echo "$OUT" | grep -q "WARNING: hook failed" || fail "failing hook not reported"
[ -f "$WORK/hook-after-fail.log" ] || fail "hooks after the failure did not run"
[ -f "$WORK/fx2/data/.first-start-complete" ] && fail "marker written despite hook failure"
echo "$OUT" | grep -q "hook failure(s)" || fail "final status did not report the failure"

# retry with the failing hook fixed: marker must appear
printf '#!/bin/sh\nexit 0\n' > "$WORK/dc/hooks/first-start.d/05-failing.sh"
chmod +x "$WORK/dc/hooks/first-start.d/05-failing.sh"
run_setup "$WORK/fx2" first-start >/dev/null 2>&1 || fail "retry run exited non-zero"
[ -f "$WORK/fx2/data/.first-start-complete" ] || fail "marker not written after hooks succeeded"

echo "PASS: setup.sh is idempotent (4 runs, state identical) and hook lifecycle is correct"
