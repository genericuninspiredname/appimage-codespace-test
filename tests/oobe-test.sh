#!/usr/bin/env bash
# OOBE (first-run welcome screen) test for .devcontainer/modules/75-oobe.sh
# + hooks/normal-start.d/10-oobe.sh + the installed desktop-welcome.
#
# Phase 1 runs the REAL coordinator (first-start, then normal-start) against
# an isolated fixture (same pattern as idempotence-test.sh) and asserts:
#   - desktop-welcome is installed into BIN_DIR and executable
#   - the Fluxbox menu gains the "Welcome Screen" entry exactly once
#     (own managed block; unrelated entries preserved)
#   - the normal-start hook exists, is executable, and the second run
#     leaves the observable state byte-identical
#   - no .oobe-shown marker is written when no display is reachable
#
# Phase 2 drives the installed desktop-welcome directly with stubs (no X
# server, no real zenity) and asserts:
#   - --print status text: environment detection (Codespace / WSL /
#     unknown), honest WebGL wording (never "available" untested),
#     resolution "unknown" without a display, GLX classification
#   - backup_status variants: no repo / empty repo / never run / backed
#     up / uncommitted changes / not pushed; markers are not documents
#   - --auto gating: marker present -> nothing shown; marker absent ->
#     dialog stub invoked and marker written; dialog failure or missing
#     display -> marker NOT written (retried next start)
#   - manual mode always shows, even with the marker present
#   - classify_renderer: software / hardware / unknown evidence rules
set -e

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
WORK=$(mktemp -d /tmp/oobe-test.XXXXXX)
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
# never see the host's X display, even on a live desktop (see run_setup)
printf '#!/bin/sh\nexit 1\n' > "$WORK/stub/xdpyinfo"
chmod +x "$WORK/stub/xdpyinfo"

# --- fixture: a copy of .devcontainer + repo ----------------------------------
cp -r "$REPO/.devcontainer" "$WORK/dc"
cp -r "$REPO" "$WORK/repo-src"
rm -rf "$WORK/repo-src/.git"
REPO_SRC="$WORK/repo-src"

# --- fixture: a home that looks "used" -----------------------------------------
H="$WORK/home"
mkdir -p "$H/.fluxbox" "$H/Files/docs" "$H/.mozilla/firefox/abc123.default-release" \
         "$H/.cache"
echo "hello" > "$H/Files/docs/note.txt"
cat > "$H/.fluxbox/menu" <<'EOF'
[begin] (Fluxbox)
[exec] (Old App) {oldapp}
[end]
EOF
printf 'session.screen0.workspaces: 2\n' > "$H/.fluxbox/init"

mkdir -p "$WORK/data" "$WORK/bin" "$WORK/xwww-dir"

# --- run helper: real coordinator, isolated env --------------------------------
ISOLATED=0
if unshare -rm true 2>/dev/null; then ISOLATED=1; fi

run_setup() { # run_setup <fixture-root> <mode>
  local fx="$1" mode="$2" inner
  inner='
    set -e
    cd "'"$fx"'/home"
    export HOME="'"$fx"'/home"
    export PATH="'"$WORK"'/stub:$PATH"
    export GIT_CONFIG_GLOBAL="'"$WORK"'/gitconfig"
    export DESKTOP_HOME="'"$fx"'/home"
    export DESKTOP_DATA_DIR="'"$fx"'/data"
    export DESKTOP_BIN_DIR="'"$fx"'/bin"
    export DESKTOP_XWWW="'"$fx"'/xwww-dir/x-www-browser"
    export DESKTOP_REPO_DIR="'"$REPO_SRC"'"
    export DESKTOP_REMOTE_URL="file://'"$WORK"'/origin.git"
    export DESKTOP_WELCOME_MAX_WAIT=1
    # 05-startup-gates.sh mkdirs its default stamp dir under /var/lib,
    # which is not writable inside the unshare fixture (and outside it
    # would touch the host) - use its documented test override
    export DESKTOP_STAMP_DIR="'"$WORK"'/stamps"
    # isolate the fixture welcome from the host it runs on: its own lock and
    # log (the hook writes DESKTOP_WELCOME_LOG), and no X display at all.
    # A failing xdpyinfo stub in PATH makes find_display fail even when the
    # host has a live desktop (Codespaces forbids unshare, so the tmpfs
    # isolation below cannot be relied on there); no setup module or hook
    # other than 75-oobe.sh uses xdpyinfo.
    export DESKTOP_WELCOME_LOCK="'"$fx"'/welcome.lock"
    export DESKTOP_WELCOME_LOG="'"$fx"'/welcome.log"
    bash "'"$WORK"'/dc/setup.sh" '"${mode:+$mode}"'
  '
  if [ "$ISOLATED" = 1 ]; then
    unshare -rm bash -c 'mount -t tmpfs tmpfs /run; mount -t tmpfs tmpfs /home; '"$inner"
  else
    [ "$(id -u)" = 0 ] || fail "not root and no user namespaces - cannot isolate"
    bash -c "$inner"
  fi
}

# The normal-start hook launches the fixture welcome detached (setsid);
# with no reachable display it exits after MAX_WAIT. Wait for that so the
# EXIT trap's teardown never races a live writer (which used to leave
# /tmp/oobe-test.* dirs behind: rm -rf failed with "Directory not empty").
wait_welcome_exit() { # <fixture-root>
  local fx="$1" i
  sleep 0.2   # setsid is asynchronous: give the welcome a moment to start
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$fx/bin/desktop-welcome" >/dev/null 2>&1 || return 0
    sleep 1
  done
  pkill -f "$fx/bin/desktop-welcome" 2>/dev/null || true
}

snapshot() {
  {
    # .oobe-lock is the transient single-instance lock of the backgrounded
    # welcome hook: present or not depending on snapshot timing, never state
    ( cd "$WORK/data"  && find . -path ./.git -prune -o -name .oobe-lock -prune -o -print \
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

# =========================================================================== phase 1
echo "== phase 1: coordinator installs the OOBE (first-start)"
run_setup "$WORK" first-start || fail "first-start run exited non-zero"
wait_welcome_exit "$WORK"
WELCOME="$WORK/bin/desktop-welcome"
[ -x "$WELCOME" ] || fail "desktop-welcome not installed/executable"
MENU="$WORK/data/private/fluxbox/menu"
[ -f "$MENU" ] || fail "fluxbox menu missing"
grep -c '^# >>> desktop-oobe >>>' "$MENU" | grep -qx 1 || fail "menu managed block not exactly once"
grep -q '\[exec\] (Welcome Screen) {desktop-welcome}' "$MENU" || fail "menu entry missing"
grep -q '\[exec\] (Old App)' "$MENU" || fail "user menu entries lost"
[ -x "$WORK/dc/hooks/normal-start.d/10-oobe.sh" ] || fail "hook missing in run fixture"
[ -x "$REPO/.devcontainer/hooks/normal-start.d/10-oobe.sh" ] || fail "hook not executable in repo"
[ ! -f "$WORK/data/.oobe-shown" ] || fail "marker written without a display"
snapshot > "$WORK/snap1"

echo "== phase 1: normal-start (hook fires; state must stay identical)"
run_setup "$WORK" normal-start || fail "normal-start run exited non-zero"
wait_welcome_exit "$WORK"
grep -c '^# >>> desktop-oobe >>>' "$MENU" | grep -qx 1 || fail "menu block duplicated on re-run"
snapshot > "$WORK/snap2"
diff "$WORK/snap1" "$WORK/snap2" > /dev/null || fail "state changed between runs"
[ ! -f "$WORK/data/.oobe-shown" ] || fail "marker written without a display (normal-start)"

# =========================================================================== phase 2
echo "== phase 2: desktop-welcome behavior (stubs, no X)"
FX="$WORK/fx"
mkdir -p "$FX/home" "$FX/data" "$FX/bin" "$FX/stub"
HOMEDIR="$FX/home" DATA_DIR="$FX/data" BIN_DIR="$FX/bin" \
  bash "$REPO/.devcontainer/modules/75-oobe.sh" || fail "module standalone run failed"
[ -x "$FX/bin/desktop-welcome" ] || fail "standalone install failed"
WELCOME="$FX/bin/desktop-welcome"

# --- zenity stub: stateful (first call exits A, later calls exit B); ----------
# --- logs every invocation; optional stderr text and stdout text --------------
# The stdout text emulates zenity 4 extra buttons (label printed to stdout,
# exit 1); the stderr text emulates both zenity 3 extra buttons (label on
# stderr, exit 5) and display-error messages.
make_zenity_stub() { # <first-exit> <later-exit> [stderr-text] [stdout-text]
  # stderr/stdout text is only emitted on the FIRST call (a label on every
  # call would make the dialog loop forever: action -> re-render -> action)
  cat > "$FX/stub/zenity" <<STUB
#!/bin/sh
n=\$(cat "$FX/zenity.count" 2>/dev/null || echo 0)
echo \$((n + 1)) > "$FX/zenity.count"
echo "zenity \$*" >> "$FX/zenity.log"
if [ "\$n" -eq 0 ]; then
  if [ -n "${3:-}" ]; then printf '%s\n' "$3" >&2; fi
  if [ -n "${4:-}" ]; then
    printf '%s\n' "$4"
    # real zenity 4 logs GTK/GVFS warnings to stderr alongside the label;
    # the dispatch must match the label inside that noise (not at the end)
    printf '(zenity:4242): Gtk-WARNING **: stray message\n' >&2
  fi
  exit $1
fi
exit $2
STUB
  chmod +x "$FX/stub/zenity"
}
rm -f "$FX/stub/xdpyinfo" "$FX/stub/xmessage" "$FX/stub/glxinfo" "$FX/stub/desktop-doctor"
# "no display" must not depend on the host having no X server: a failing
# xdpyinfo stub makes find_display fail on every host (the socket fallback
# branch only runs when xdpyinfo is absent from PATH entirely)
no_display_stub() {
  printf '#!/bin/sh\nexit 1\n' > "$FX/stub/xdpyinfo"
  chmod +x "$FX/stub/xdpyinfo"
}
no_display_stub

# Stub the Browser action target from the start: the --auto/manual gating
# subtests below dispatch the Browser action (zenity stub exit 0 = OK),
# and a REAL x-www-browser (Firefox on the desktop image) would run
# detached with HOME=$FX/home and keep writing its profile into $WORK
# after the test exits - the EXIT trap's rm -rf then races it ("Directory
# not empty") and /tmp/oobe-test.* dirs are left behind.
printf '#!/bin/sh\necho "x-www-browser $*" >> "%s/x-www-browser.log"\n' "$FX" \
  > "$FX/stub/x-www-browser"
chmod +x "$FX/stub/x-www-browser"

run_welcome() { # runs the installed script with fixture env + stub PATH
  env HOME="$FX/home" DESKTOP_DATA_DIR="$FX/data" \
      DESKTOP_WELCOME_MAX_WAIT=1 DESKTOP_WELCOME_LOCK="$FX/lock" \
      PATH="$FX/stub:$PATH" "$WELCOME" "$@"
}

# --- --print: environment detection ------------------------------------------
echo "  --print: environment detection"
out=$(CODESPACES=true CODESPACE_NAME= run_welcome --print)
grep -q 'Environment: Linux (GitHub Codespace)' <<< "$out" || fail "Codespace not detected"
grep -q 'CPU:.*cores' <<< "$out" || fail "CPU line missing"
grep -q 'Memory:.*GiB' <<< "$out" || fail "Memory line missing"
grep -q 'Screen:.*unknown (no reachable X display)' <<< "$out" || fail "screen not unknown without display"

out=$(CODESPACES= CODESPACE_NAME= DESKTOP_WELCOME_PROC_VERSION='Linux version 5.15.x-microsoft-standard-WSL2' run_welcome --print)
grep -q 'Environment: Windows host (WSL)' <<< "$out" || fail "WSL host not detected"

out=$(CODESPACES= CODESPACE_NAME= DESKTOP_WELCOME_PROC_VERSION='Linux version 6.1 plain' run_welcome --print)
grep -q 'Environment: Unknown host' <<< "$out" || fail "unknown host not honest"

# --- --print: honest WebGL wording --------------------------------------------
echo "  --print: honest WebGL wording (never 'available' without a test)"
out=$(run_welcome --print)
grep -q 'WebGL:.*no test result kept here' <<< "$out" || fail "WebGL status not honest about kept state"
if grep -q 'WebGL:.*available' <<< "$out"; then fail "WebGL claimed available without a test"; fi
grep -q 'desktop-doctor (diagnostics branch) is not installed' <<< "$out" || fail "missing desktop-doctor not stated"
# with a desktop-doctor stub installed, the wording switches to the tool
printf '#!/bin/sh\nexit 0\n' > "$FX/stub/desktop-doctor"; chmod +x "$FX/stub/desktop-doctor"
out=$(run_welcome --print)
grep -q 'WebGL Test button runs desktop-doctor' <<< "$out" || fail "desktop-doctor presence not used"
rm -f "$FX/stub/desktop-doctor"

# --- --print: resolution + GLX evidence need a display ------------------------
echo "  --print: resolution and GLX evidence (stubbed display)"
cat > "$FX/stub/xdpyinfo" <<'EOF'
#!/bin/sh
echo "dimensions:    1024x768 pixels"
echo "depth of root window:    24 planes"
exit 0
EOF
cat > "$FX/stub/glxinfo" <<'EOF'
#!/bin/sh
echo "OpenGL renderer string: llvmpipe (LLVM 15.0.7, 256 bits)"
echo "OpenGL vendor string: Mesa/X.org"
EOF
chmod +x "$FX/stub/xdpyinfo" "$FX/stub/glxinfo"
out=$(DESKTOP_WELCOME_DISPLAY=:9 run_welcome --print)
grep -q 'Screen:.*1024x768, 24-bit (display :9)' <<< "$out" || fail "resolution not picked up from xdpyinfo"
grep -q 'GLX:.*software rendering (llvmpipe' <<< "$out" || fail "GLX software renderer not classified"
rm -f "$FX/stub/xdpyinfo" "$FX/stub/glxinfo"
no_display_stub

# --- backup_status variants ----------------------------------------------------
echo "  backup_status variants"
out=$(run_welcome --print)
grep -q 'Backup:  unknown (persistent data dir not initialized)' <<< "$out" || fail "no-repo backup state wrong"
# repo with no commits
git -C "$FX/data" init -q -b desktop-data
out=$(run_welcome --print)
grep -q 'Backup:  never run (the backup repository has no commits)' <<< "$out" || fail "empty-repo backup state wrong"
# a pushed backup commit, a second local-only one, and an uncommitted file
mkdir -p "$FX/data/files" && echo doc > "$FX/data/files/a.txt"
git -C "$FX/data" add -A -- files/ 2>/dev/null || true
git -C "$FX/data" -c user.name=t -c user.email=t@t commit -qm "backup 2026-10-22_10:00" -- files/
git -C "$FX/data" remote add origin "$WORK/origin.git"
git -C "$FX/data" push -q origin desktop-data 2>/dev/null || true
echo doc2 > "$FX/data/files/b.txt"
git -C "$FX/data" add -A -- files/ && git -C "$FX/data" -c user.name=t -c user.email=t@t \
  commit -qm "backup 2026-10-22_11:00" -- files/
echo uncommitted > "$FX/data/files/c.txt"
out=$(run_welcome --print)
grep -q 'Backup:  last backup 2026-10-22 (2 total)' <<< "$out" || fail "backup count/date wrong"
grep -q '1 uncommitted change(s) in ~/Files not backed up yet' <<< "$out" || fail "dirty files not reported"
grep -q 'latest backup not pushed to GitHub (local only)' <<< "$out" || fail "unpushed state not reported"
# markers at the data-dir root must NOT count as unbacked-up documents
touch "$FX/data/.oobe-shown"
out=$(run_welcome --print)
if grep -q '\.oobe.*not backed up' <<< "$out"; then fail "marker counted as a document"; fi
[ "$(grep -c 'uncommitted change' <<< "$out")" = 1 ] || fail "marker changed the dirty count"
rm -f "$FX/data/.oobe-shown"

# --- --auto gating ------------------------------------------------------------
echo "  --auto gating with a stubbed dialog"
MARKER="$FX/data/.oobe-shown"
cat > "$FX/stub/xdpyinfo" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FX/stub/xdpyinfo"
make_zenity_stub 0 1      # first call: Browser action; later: Close
rm -f "$MARKER" "$FX/zenity.log" "$FX/zenity.count"
run_welcome --auto >/dev/null 2>&1 || fail "--auto failed with a working dialog stub"
[ -f "$FX/zenity.log" ] || fail "dialog not shown on first launch"
[ -f "$MARKER" ] || fail "marker not written after a shown dialog"
[ -d "$FX/lock" ] && fail "lock directory not cleaned up after exit"
# second run: marker present -> nothing shown, exit 0
rm -f "$FX/zenity.log" "$FX/zenity.count"
run_welcome --auto >/dev/null 2>&1 || fail "--auto failed when marker present"
[ -f "$FX/zenity.log" ] && fail "dialog shown again although marker exists"
[ -f "$MARKER" ] || fail "marker vanished"

echo "  --auto: dialog failure leaves the marker absent (retried next start)"
rm -f "$MARKER" "$FX/zenity.count"
make_zenity_stub 1 1 "Gtk-WARNING **: cannot open display"
run_welcome --auto >/dev/null 2>&1 && fail "--auto succeeded despite dialog failure"
[ -f "$FX/zenity.log" ] || fail "dialog stub not invoked"
[ -f "$MARKER" ] && fail "marker written although the dialog failed"

echo "  --auto: stale lock (dead holder) is stolen, dialog shows"
make_zenity_stub 0 1
rm -f "$MARKER" "$FX/zenity.log" "$FX/zenity.count"
mkdir -p "$FX/lock"
echo 999999 > "$FX/lock/pid"     # a PID that cannot be alive
run_welcome --auto >/dev/null 2>&1 || fail "--auto failed with a stale lock"
[ -f "$FX/zenity.log" ] || fail "dialog not shown despite stale lock"
[ -f "$MARKER" ] || fail "marker not written after stale-lock run"
[ -d "$FX/lock" ] && fail "stale lock not replaced/cleaned"

echo "  --auto: no display -> no dialog, no marker, exit non-zero"
make_zenity_stub 0 1
rm -f "$MARKER" "$FX/zenity.log" "$FX/zenity.count"
no_display_stub
run_welcome --auto >/dev/null 2>&1 && fail "--auto succeeded without a display"
[ -f "$FX/zenity.log" ] && fail "dialog shown without a display"
[ -f "$MARKER" ] && fail "marker written without a display"

echo "  manual mode always shows (marker present)"
touch "$MARKER"
make_zenity_stub 0 1
cat > "$FX/stub/xdpyinfo" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FX/stub/xdpyinfo"
rm -f "$FX/zenity.log" "$FX/zenity.count"
run_welcome >/dev/null 2>&1 || fail "manual run failed with working stubs"
[ -f "$FX/zenity.log" ] || fail "manual run did not show the dialog"

# --- extra-button dispatch (regression: zenity 4 changed the protocol) ----------
echo "  extra buttons: zenity 4 style (exit 1, label on stdout)"
# stubs that make the actions observable
for cmd in nautilus desktop-doctor x-www-browser; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/%s.log"\n' "$cmd" "$FX" "$cmd" > "$FX/stub/$cmd"
  chmod +x "$FX/stub/$cmd"
done
cat > "$FX/stub/xterm" <<STUB
#!/bin/sh
echo "xterm \$*" >> "$FX/xterm.log"
STUB
chmod +x "$FX/stub/xterm"

# Files -> nautilus on the Files directory
make_zenity_stub 1 1 "" "Files"
rm -f "$FX/nautilus.log" "$FX/zenity.log" "$FX/zenity.count"
run_welcome >/dev/null 2>&1
grep -q "nautilus .*Files" "$FX/nautilus.log" 2>/dev/null \
  || fail "Files button did not dispatch to nautilus"

# WebGL Test -> desktop-doctor (diagnostics interface) in a terminal
make_zenity_stub 1 1 "" "WebGL Test"
rm -f "$FX/xterm.log" "$FX/zenity.log" "$FX/zenity.count"
run_welcome >/dev/null 2>&1
grep -q "desktop-doctor" "$FX/xterm.log" 2>/dev/null \
  || fail "WebGL Test button did not dispatch to desktop-doctor"

# Performance Settings -> its info window (zenity --text-info)
make_zenity_stub 1 1 "" "Performance Settings"
rm -f "$FX/zenity.log" "$FX/zenity.count"
run_welcome >/dev/null 2>&1
grep -q -- "--text-info --title Performance Settings" "$FX/zenity.log" \
  || fail "Performance Settings button did not open its window"

# Stop Instructions -> its info window
make_zenity_stub 1 1 "" "Stop Instructions"
rm -f "$FX/zenity.log" "$FX/zenity.count"
run_welcome >/dev/null 2>&1
grep -q -- "--text-info --title Stopping the codespace" "$FX/zenity.log" \
  || fail "Stop Instructions button did not open its window"

# Browser (OK button) -> x-www-browser
make_zenity_stub 0 1
rm -f "$FX/x-www-browser.log" "$FX/zenity.log" "$FX/zenity.count"
run_welcome >/dev/null 2>&1
grep -q "x-www-browser" "$FX/x-www-browser.log" 2>/dev/null \
  || fail "Browser button did not dispatch to x-www-browser"

echo "  extra buttons: zenity 3 style (exit 5, label on stderr)"
make_zenity_stub 5 5 "Files"
rm -f "$FX/nautilus.log" "$FX/zenity.log" "$FX/zenity.count"
# exit 1 expected: the re-rendered dialog "fails" (timeout semantics)
run_welcome >/dev/null 2>&1 || true
grep -q "nautilus .*Files" "$FX/nautilus.log" 2>/dev/null \
  || fail "zenity 3 Files button did not dispatch to nautilus"

# zenity 3 timeout: exit 5 with no label must NOT be treated as Close
# (no marker write; the run fails so onboarding retries next launch)
rm -f "$MARKER"
make_zenity_stub 5 5
cat > "$FX/stub/xdpyinfo" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FX/stub/xdpyinfo"
run_welcome --auto >/dev/null 2>&1 \
  && fail "zenity-3 timeout (exit 5, no label) wrongly treated as success"
[ -f "$MARKER" ] && fail "timeout dialog marked the first launch done"
rm -f "$FX/stub/nautilus" "$FX/stub/desktop-doctor" \
      "$FX/stub/x-www-browser" "$FX/stub/xterm"

# --- classify_renderer evidence rules -------------------------------------------
echo "  classify_renderer evidence rules"
classify() { run_welcome --classify-renderer "$1"; }
[ "$(classify 'llvmpipe (LLVM 15)')" = "software" ] || fail "llvmpipe not software"
[ "$(classify 'ANGLE (Intel, Mesa Intel(R) UHD Graphics)')" = "hardware" ] || fail "real GPU not hardware"
[ "$(classify '')" = "unknown" ] || fail "empty renderer not unknown"
[ "$(classify 'WebGL is disabled')" = "unknown" ] || fail "disabled string not unknown"

# --- cgroup memory is converted from BYTES ---------------------------------------
echo "  cgroup memory line (bytes, not KiB - regression: was 1024x too large)"
[ "$(run_welcome --cgroup-mem 1073741824 4294967296)" = "1.0/4.0 GiB container (cgroup limit)" ] \
  || fail "cgroup memory mis-scaled (1 GiB/4 GiB input)"
[ "$(run_welcome --cgroup-mem 536870912 1073741824)" = "0.5/1.0 GiB container (cgroup limit)" ] \
  || fail "cgroup memory mis-scaled (0.5 GiB/1 GiB input)"

echo "PASS: OOBE installed idempotently; gating, status text and fallbacks verified"
