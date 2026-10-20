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
#    because /workspaces is preserved on rebuild; deletion of the codespace
#    loses it unless backed up - see the backup script below).
# ---------------------------------------------------------------------------
if [ ! -d "$DATA_DIR/.git" ]; then
  mkdir -p "$DATA_DIR/files" "$DATA_DIR/private"
  git -C "$DATA_DIR" init -q -b desktop-data
  git -C "$DATA_DIR" remote add origin "$REMOTE_URL"
  # Restore from GitHub if a previous backup exists (fresh codespace only;
  # never run on an existing data dir, so nothing on disk gets overwritten)
  if git -C "$DATA_DIR" fetch -q origin desktop-data 2>/dev/null; then
    git -C "$DATA_DIR" checkout -q FETCH_HEAD -- . 2>/dev/null || true
    git -C "$DATA_DIR" branch -q --set-upstream-to=origin/desktop-data desktop-data 2>/dev/null || true
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
# 2. Visible "Files" folder + persistent app settings (symlinked into /root,
#    which resets on rebuild; the data dir does not)
# ---------------------------------------------------------------------------
link_dir() { # link_dir <real path> <persistent target>
  local src="$1" dest="$2"
  [ -L "$src" ] && return 0                 # already linked
  mkdir -p "$(dirname "$src")" "$(dirname "$dest")"
  if [ -d "$dest" ]; then
    rm -rf "$src"                            # keep the persisted version
  elif [ -d "$src" ]; then
    mv "$src" "$dest"                        # first run: move existing in
  fi
  mkdir -p "$dest"
  ln -sfn "$dest" "$src"
}

link_dir "$HOMEDIR/Files"                     "$DATA_DIR/files"
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
# ---------------------------------------------------------------------------
mkdir -p "$BIN_DIR"
if [ ! -f "$BIN_DIR/desktop-backup" ]; then
  cat > "$BIN_DIR/desktop-backup" <<'BK'
#!/usr/bin/env bash
set -e
DATA_DIR="${DESKTOP_DATA_DIR:-/workspaces/desktop-data}"
cd "$DATA_DIR"
git add -A -- files/ .gitignore
if git diff --cached --quiet; then
  echo "Nothing new to back up."
  exit 0
fi
git commit -qm "backup $(date -u +%Y-%m-%d_%H:%M)"
if git push -q -u origin desktop-data 2>/dev/null; then
  echo "Backed up to GitHub (branch: desktop-data)."
else
  echo "Saved locally, but push to GitHub FAILED (network or permissions)."
  exit 1
fi
BK
  chmod +x "$BIN_DIR/desktop-backup"
fi

# ---------------------------------------------------------------------------
# 4. Desktop menu entries (menu is written once by desktop-lite; guarded so
#    this is safe to run repeatedly)
# ---------------------------------------------------------------------------
MENU="$HOMEDIR/.fluxbox/menu"
if [ -f "$MENU" ] && ! grep -q "Helium Browser" "$MENU"; then
  awk -v home="$HOMEDIR" '
    BEGIN { apps = "[exec] (Helium Browser) {/opt/apps/helium/AppRun --no-sandbox}\n[exec] (OBS Studio) {/opt/apps/obs/AppRun}\n[exec] (Files) {nautilus " home "/Files}\n[exec] (Back Up Files) {tilix -e desktop-backup}\n[exec] (Start Audio) {pulseaudio -D --exit-idle-time=-1}\n[exec] (Volume Control) {pavucontrol}" }
    !done && /\[begin\]/ { print; print apps; done=1; next }
    { print }
  ' "$MENU" > "$MENU.new" && mv "$MENU.new" "$MENU"
fi

echo "Setup complete - open the forwarded port 6080 in your browser."
