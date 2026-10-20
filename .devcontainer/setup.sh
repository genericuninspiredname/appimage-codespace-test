#!/usr/bin/env bash
# Idempotent setup: persistent file system + app settings + backup tool.
# Runs on codespace creation (postCreate) and every start (postStart).
set -e

HOMEDIR="${DESKTOP_HOME:-$HOME}"
DATA_DIR="${DESKTOP_DATA_DIR:-/workspaces/desktop-data}"
BIN_DIR="${DESKTOP_BIN_DIR:-/usr/local/bin}"
REPO_DIR="${DESKTOP_REPO_DIR:-}"
if [ -z "$REPO_DIR" ]; then
  REPO_DIR=$(dirname "$(find /workspaces -maxdepth 2 -name .git -type d 2>/dev/null | head -1)")
  [ -d "$REPO_DIR" ] || REPO_DIR=/workspaces/appimage-codespace-test
fi
REMOTE_URL="${DESKTOP_REMOTE_URL:-$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo https://github.com/genericuninspiredname/appimage-codespace-test.git)}"

# ---------------------------------------------------------------------------
# 1. Persistent data directory (survives stop/start and container rebuilds,
#    because /workspaces is preserved on rebuild; deleting the codespace
#    loses it unless backed up - see the backup script below).
#    Never overwrites anything already on disk: restore only fills a fresh
#    git repo, and merges (never replaces) existing folders.
# ---------------------------------------------------------------------------
if [ ! -d "$DATA_DIR/.git" ]; then
  git -C "$DATA_DIR" init -q -b desktop-data 2>/dev/null || { mkdir -p "$DATA_DIR" && git -C "$DATA_DIR" init -q -b desktop-data; }
  git -C "$DATA_DIR" remote remove origin >/dev/null 2>&1 || true
  git -C "$DATA_DIR" remote add origin "$REMOTE_URL"
  # Restore from GitHub if a previous backup exists. This makes the local
  # branch share the remote's history so future backups push cleanly.
  if git -C "$DATA_DIR" fetch -q origin desktop-data 2>/dev/null; then
    if git -C "$DATA_DIR" checkout -q -B desktop-data FETCH_HEAD 2>/dev/null; then
      git -C "$DATA_DIR" branch -q --set-upstream-to=origin/desktop-data desktop-data 2>/dev/null || true
    else
      echo "WARNING: could not restore backup cleanly (files already present?). Continuing without restore." >&2
    fi
  fi
fi
mkdir -p "$DATA_DIR/files" "$DATA_DIR/private"
git -C "$DATA_DIR" config user.name  >/dev/null 2>&1 || git -C "$DATA_DIR" config user.name "codespace"
git -C "$DATA_DIR" config user.email >/dev/null 2>&1 || git -C "$DATA_DIR" config user.email "codespace@users.noreply.github.com"

# Keep credentials/profiles and big binaries out of git (backup = documents only)
if [ ! -f "$DATA_DIR/.gitignore" ]; then
  cat > "$DATA_DIR/.gitignore" <<'IGN'
private/
*.mkv
*.mp4
*.avi
*.mov
*.webm
*.flv
*.wav
*.zip
*.tar.gz
*.7z
IGN
fi

# ---------------------------------------------------------------------------
# 2. Visible "Files" folder + persistent app settings (symlinked into $HOME,
#    which resets on rebuild; the data dir does not). Existing content is
#    always preserved: new files are merged in, existing files are kept.
# ---------------------------------------------------------------------------
link_dir() { # link_dir <src> <dest> [migrate]
  local src="$1" dest="$2" migrate="${3:-0}"
  [ -L "$src" ] && return 0                 # already linked
  mkdir -p "$(dirname "$src")" "$(dirname "$dest")"
  if [ -d "$dest" ]; then
    if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
      if [ "$migrate" = 1 ]; then
        # Whole-directory import for user documents: the entire source tree
        # (files, symlinks, empty folders - everything) is moved as-is into
        # the persistent destination, so no version can be lost. Only after
        # the move succeeds is the original path replaced by the symlink.
        local import_dir
        import_dir="$dest/Imported-from-home-$(date -u +%Y%m%d-%H%M%S)-$$"
        if ! mv "$src" "$import_dir" 2>/dev/null; then
          echo "WARNING: could not import $src into $dest; leaving it untouched" >&2
          return 0
        fi
      fi
      # For app configs (migrate=0) the persisted version wins; on rebuild
      # the source is only the fresh image default, so dropping it is safe.
    fi
    rm -rf "$src"
  elif [ -d "$src" ]; then
    mv "$src" "$dest"                        # first run: move existing in
  fi
  mkdir -p "$dest"
  ln -sfn "$dest" "$src"
}

link_dir "$HOMEDIR/Files"                     "$DATA_DIR/files" 1
link_dir "$HOMEDIR/.config/net.imput.helium"  "$DATA_DIR/private/net.imput.helium"
link_dir "$HOMEDIR/.config/obs-studio"        "$DATA_DIR/private/obs-studio"
link_dir "$HOMEDIR/.fluxbox"                  "$DATA_DIR/private/fluxbox"

# Codespaces blocks unshare/userns; skip the pkgforge AppImage namespaces
# check so Helium (and other pkgforge apps) launch without a dialog.
mkdir -p "$HOMEDIR/.cache"
touch "$HOMEDIR/.cache/.disable-namespaces-check"

# ---------------------------------------------------------------------------
# 3. Backup tool: explicitly backs up ~/Files (documents only, never
#    profiles/credentials) to the desktop-data branch of this repo.
#    Reinstalled on every setup run so fixes reach existing codespaces.
# ---------------------------------------------------------------------------
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/desktop-backup" <<'BK'
#!/usr/bin/env bash
set -e
DATA_DIR="${DESKTOP_DATA_DIR:-/workspaces/desktop-data}"
cd "$DATA_DIR"
git add -A -- files/ .gitignore
committed=0
if ! git diff --cached --quiet; then
  git commit -qm "backup $(date -u +%Y-%m-%d_%H:%M)"
  committed=1
fi
# Always attempt the push: retries after earlier failures, even with no
# new changes, so locally-committed backups reach GitHub eventually.
# No automatic rebase/merge: a diverged remote is reported as a failure so
# documents are never rewritten with conflict markers.
if git push -q -u origin desktop-data 2>/tmp/desktop-push.err; then
  if [ "$committed" = 1 ]; then
    echo "Backed up to GitHub (branch: desktop-data)."
  else
    echo "Everything already backed up."
  fi
else
  echo "Push to GitHub FAILED:" >&2
  head -3 /tmp/desktop-push.err >&2
  echo "Your changes are saved locally - run this again later to retry." >&2
  exit 1
fi
BK
chmod +x "$BIN_DIR/desktop-backup"

# ---------------------------------------------------------------------------
# 4. Desktop menu entries (managed block: replaced wholesale on every run,
#    so upgrades add entries without duplicating old ones)
# ---------------------------------------------------------------------------
MENU="$HOMEDIR/.fluxbox/menu"
if [ -f "$MENU" ]; then
  awk -v home="$HOMEDIR" '
    BEGIN {
      block = "# >>> desktop-apps >>>\n[exec] (Helium Browser) {/opt/apps/helium/AppRun --no-sandbox}\n[exec] (OBS Studio) {/opt/apps/obs/AppRun}\n[exec] (Files) {nautilus " home "/Files}\n[exec] (Back Up Files) {tilix -e desktop-backup}\n[exec] (Start Audio) {pulseaudio -D --exit-idle-time=-1}\n[exec] (Volume Control) {pavucontrol}\n# <<< desktop-apps <<<"
      inblock = 0
    }
    /^# >>> desktop-apps >>>/ { inblock = 1; next }
    /^# <<< desktop-apps <<</ { inblock = 0; next }
    inblock { next }
    # drop entries written by older versions of this script
    /\[exec\] \(Helium Browser\)/ { next }
    /\[exec\] \(OBS Studio\)/ { next }
    /\[exec\] \(Start Audio\)/ { next }
    /\[exec\] \(Volume Control\)/ { next }
    /\[exec\] \(Files\)/ { next }
    /\[exec\] \(Back Up Files\)/ { next }
    !done && /\[begin\]/ { print; print block; done = 1; next }
    { print }
  ' "$MENU" > "$MENU.new" && mv "$MENU.new" "$MENU"
fi

echo "Setup complete - open the forwarded port 6080 in your browser."
