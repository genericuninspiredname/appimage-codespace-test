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
link_dir "$HOMEDIR/.mozilla"                   "$DATA_DIR/private/mozilla"
link_dir "$HOMEDIR/.fluxbox"                  "$DATA_DIR/private/fluxbox"

# Codespaces blocks unshare/userns; skip the pkgforge AppImage namespaces
# check so Firefox (and other pkgforge apps) launch without a dialog.
mkdir -p "$HOMEDIR/.cache"
touch "$HOMEDIR/.cache/.disable-namespaces-check"

# Browser launcher: Firefox. Filters Chromium-specific flags it does not
# understand, and disables its content-process sandbox because Codespaces
# blocks the user namespaces it requires (Firefox shows a warning banner
# about this - expected in this environment).
XWWW="${DESKTOP_XWWW:-/usr/local/bin/x-www-browser}"
mkdir -p "$(dirname "$XWWW")"
cat > "$XWWW" <<'WB'
#!/bin/bash
flags=()
for a in "$@"; do
  case "$a" in
    --disable-dev-shm-usage|--disable-gpu|--no-sandbox) ;;
    *) flags+=("$a") ;;
  esac
done
exec env MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 \
  /opt/apps/firefox/AppRun "${flags[@]}"
WB
chmod +x "$XWWW"

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
  awk -v home="$HOMEDIR" -v fluxdir="$HOMEDIR/.fluxbox" '
    BEGIN {
      block = "# >>> desktop-apps >>>\n[exec] (Run Program...) {fbrun}\n[exec] (Files) {nautilus " home "/Files}\n[exec] (Keyboard Shortcuts) {mousepad " fluxdir "/SHORTCUTS}\n[exec] (Back Up Files) {tilix -e desktop-backup}\n[restart] (Apply Desktop Updates) {}\n# <<< desktop-apps <<<"
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
    !done && /\[begin\]/ { print; print block; done = 1; next }
    { print }
  ' "$MENU" > "$MENU.new" && mv "$MENU.new" "$MENU"
fi

# ---------------------------------------------------------------------------
# 5. Desktop polish: taskbar, window switching, wallpaper, WebGL. All managed
#    blocks/files, replaced on every run so upgrades apply cleanly.
# ---------------------------------------------------------------------------
FLUXDIR="$HOMEDIR/.fluxbox"

# Wallpaper (copied from the repo so it survives ~/.fluxbox being persisted)
mkdir -p "$FLUXDIR/backgrounds"
[ -f "$REPO_DIR/assets/wallpaper.png" ] && \
  cp -f "$REPO_DIR/assets/wallpaper.png" "$FLUXDIR/backgrounds/wallpaper.png"

# --- init: taskbar layout + workspaces (managed block at the END of the file:
# fluxbox keeps the last occurrence of a duplicate resource, so our values
# must come after any earlier ones) ---
INIT="$FLUXDIR/init"
init_block="# >>> desktop-init >>>
session.screen0.workspaces: 4
session.screen0.workspaceNames: Main, Web, Extra, Four
session.screen0.workspacewarping: true
session.screen0.toolbar.visible: true
session.screen0.toolbar.layer: Dock
session.screen0.toolbar.placement: BottomCenter
session.screen0.toolbar.autoHide: false
session.screen0.toolbar.tools: RootMenu, workspacename, prevworkspace, nextworkspace, iconbar, systemtray, prevwindow, nextwindow, clock
session.screen0.iconbar.mode: Workspace
session.screen0.iconbar.usePixmap: true
session.screen0.iconbar.alignment: Relative
session.screen0.focusNewWindows: true
session.screen0.focusLastWindow: true
session.screen0.strftimeFormat: %a %b %d %l:%M %p
session.styleOverlay: $FLUXDIR/overlay
# <<< desktop-init <<<"
if [ -f "$INIT" ]; then
  awk -v block="$init_block" '
    /^# >>> desktop-init >>>/ { inb = 1; next }
    /^# <<< desktop-init <<</ { inb = 0; next }
    inb { next }
    { print }
    END { print block }
  ' "$INIT" > "$INIT.new" && mv "$INIT.new" "$INIT"
else
  printf '%s\n' "$init_block" > "$INIT"
fi

# Style overlay: wallpaper + readable taskbar labels (the qnx-photon style
# ships no iconbar colors, so window titles wash out without these).
# Managed block: fluxbox also writes user style changes to this file.
OVERLAY="$FLUXDIR/overlay"
overlay_block="# >>> desktop-overlay >>>
background: aspect
background.pixmap: $FLUXDIR/backgrounds/wallpaper.png
toolbar.iconbar.focused: flat solid
toolbar.iconbar.focused.color: rgb:FC/F9/DF
toolbar.iconbar.focused.textColor: rgb:20/20/20
toolbar.iconbar.unfocused: flat solid
toolbar.iconbar.unfocused.color: rgb:DB/DA/DB
toolbar.iconbar.unfocused.textColor: rgb:45/45/45
# <<< desktop-overlay <<<"
if [ -f "$OVERLAY" ]; then
  awk -v block="$overlay_block" '
    /^# >>> desktop-overlay >>>/ { inb = 1; next }
    /^# <<< desktop-overlay <<</ { inb = 0; next }
    inb { next }
    { print }
    END { print block }
  ' "$OVERLAY" > "$OVERLAY.new" && mv "$OVERLAY.new" "$OVERLAY"
else
  printf '%s\n' "$overlay_block" > "$OVERLAY"
fi

# --- keys: window switching that works through noVNC (the browser/OS usually
# captures Alt+Tab, so Alt+` is the practical binding there) ---
KEYS="$FLUXDIR/keys"
keys_block="# >>> desktop-keys >>>
# Alt+\` cycles windows too: browsers/OSes usually capture Alt+Tab when the
# desktop is used through noVNC, and Alt+\` is not intercepted.
Mod1 Grave :NextWindow {groups} (workspace=[current])
Mod1 Shift Grave :PrevWindow {groups} (workspace=[current])
# Alt+1..4 jump straight to a workspace
Mod1 1 :Workspace 1
Mod1 2 :Workspace 2
Mod1 3 :Workspace 3
Mod1 4 :Workspace 4
# <<< desktop-keys <<<"
if [ ! -f "$KEYS" ]; then
  # First run: fluxbox would create this from /etc/X11/fluxbox/keys at first
  # start (postCreate runs before that); write that default plus our block.
  cat /etc/X11/fluxbox/keys > "$KEYS" 2>/dev/null || true
  [ -s "$KEYS" ] || printf 'OnDesktop Mouse3 :RootMenu\n' > "$KEYS"
  printf '%s\n' "$keys_block" >> "$KEYS"
elif ! grep -q '^# >>> desktop-keys >>>' "$KEYS"; then
  printf '%s\n' "$keys_block" >> "$KEYS"
else
  awk '
    /^# >>> desktop-keys >>>/ { inb = 1; next }
    /^# <<< desktop-keys <<</ { inb = 0; next }
    inb { next }
    { print }
  ' "$KEYS" > "$KEYS.new" && mv "$KEYS.new" "$KEYS"
  printf '%s\n' "$keys_block" >> "$KEYS"
fi

# --- shortcuts cheat sheet (opened from the menu) ---
cat > "$FLUXDIR/SHORTCUTS" <<'DOC'
Keyboard shortcuts
==================

Switching windows
  Alt+Tab / Alt+Shift+Tab    cycle windows (needs a real VNC client;
                             browsers usually capture Alt+Tab)
  Alt+` (backtick)          cycle windows - use this through noVNC
  Alt+Shift+`                cycle backwards
  Taskbar arrows / scroll    click the < > buttons or scroll the taskbar

Workspaces (4)
  Ctrl+Alt+Left / Right      previous / next workspace
  Scroll on the desktop      previous / next workspace
  Alt+1 .. Alt+4             jump to workspace 1-4
  Super+Left / Right         send window to prev/next workspace
  Ctrl+Super+Left / Right    take window with you

Windows
  Alt+F2                     run dialog (or menu: Run Program...)
  Alt+F4 / Alt+F9            close / minimize
  Alt+F10 / Alt+F11          maximize / fullscreen
  Alt+Space                  window menu
  Alt+drag                   move; Alt+right-drag resizes
  Ctrl+drag titlebar         onto another window to group them as tabs
  Double-click titlebar      shade the window
DOC

# --- WebGL: the codespace has no GPU; Firefox renders WebGL in software
# (Mesa software rasterizer on the CPU). Force it on so blocklist entries
# for software renderers can not silently disable it. Written to every
# profile on each start; applied when Firefox next launches. ---
for prof in "$HOMEDIR"/.mozilla/firefox/*.default-release \
            "$HOMEDIR"/.mozilla/firefox/*.default; do
  [ -d "$prof" ] || continue
  cat > "$prof/user.js" <<'JS'
user_pref("webgl.force-enabled", true);
user_pref("webgl.disabled", false);
JS
done

# --- apply to a running desktop: this script can run after the desktop has
# already started (postStart). Restarting fluxbox re-reads init/keys/menu/
# overlay, keeps every window open, and takes under a second. ---
if pgrep -x fluxbox >/dev/null 2>&1; then
  DISPLAY="${DISPLAY:-:1}" fluxbox-remote restart >/dev/null 2>&1 || true
fi

echo "Setup complete - open the forwarded port 6080 in your browser."
