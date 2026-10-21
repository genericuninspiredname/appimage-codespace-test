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
# Roblox/Sober data (client downloads, login, settings) survives rebuilds
link_dir "$HOMEDIR/.var/app/org.vinegarhq.Sober"  "$DATA_DIR/private/sober"
link_dir "$HOMEDIR/.fluxbox"                  "$DATA_DIR/private/fluxbox"

# ---------------------------------------------------------------------------
# 1b. Sober runtime library overlay. The image build installs Sober
#     (flatpak) and writes the overlay script; it must run AFTER the
#     devcontainer features (which apt-install packages that overwrite
#     the overlaid files), i.e. here on every create/start. Idempotent.
# ---------------------------------------------------------------------------
if [ -f /usr/local/share/sober-overlay.py ]; then
  python3 /usr/local/share/sober-overlay.py >/dev/null 2>&1 || true
  ldconfig 2>/dev/null || true
fi

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
# 2a. Roblox runs as a dedicated non-root user. Sober's anti-tamper
#     refuses to start the game client when /proc/self/status shows
#     Uid: 0 (it dies with a NULL-deref inside libloader.so before any
#     UI appears), and running desktop apps as root is bad practice
#     anyway. The user gets the same persistent Sober data dir as before.
# ---------------------------------------------------------------------------
RBX_USER=roblox
if ! id "$RBX_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$RBX_USER"
fi
RBX_UID=$(id -u "$RBX_USER")
mkdir -p /run/user/"$RBX_UID"
chown "$RBX_USER" /run/user/"$RBX_UID" && chmod 700 /run/user/"$RBX_UID"
RBX_APP="/home/$RBX_USER/.var/app/org.vinegarhq.Sober"
mkdir -p "/home/$RBX_USER/.var/app" "$DATA_DIR/private/sober"
if [ -d "$RBX_APP" ] && [ ! -L "$RBX_APP" ]; then
  # migrate a pre-existing real directory (e.g. from manual testing) into
  # the persistent data dir, then replace it with the symlink
  cp -a "$RBX_APP/." "$DATA_DIR/private/sober/" 2>/dev/null || true
  rm -rf "$RBX_APP"
fi
ln -sfn "$DATA_DIR/private/sober" "$RBX_APP"
chown -R "$RBX_USER:$RBX_USER" "/home/$RBX_USER/.var" "$DATA_DIR/private/sober"
# Sober's log rotator leaves 'latest.log' as a symlink to the newest log;
# ones created by earlier root runs point into /root, which this user cannot
# read (the app then dies with a filesystem_error at startup). Remove any
# symlink that points back into /root.
find "$DATA_DIR/private/sober" -type l -lname '/root/*' -delete 2>/dev/null || true

# /app must be a REAL directory, not a symlink: Sober's launcher verifies
# its own /proc/self/exe path and expects the flatpak sandbox layout
# (/app/bin/sober). Hardlinks cost no extra disk. Rebuilt every setup run
# so flatpak updates flow through (old inodes are garbage-collected by
# flatpak; a stale copy would keep the old app version alive).
APP_FILES=/var/lib/flatpak/app/org.vinegarhq.Sober/current/active/files
if [ -d "$APP_FILES/bin" ]; then
  rm -rf /app.new
  cp -al "$APP_FILES" /app.new && rm -rf /app && mv /app.new /app
  printf '[Environment]\n' > /.flatpak-info
fi

# Small /usr/share bits the flatpak sandbox normally provides (ALSA config,
# the runtime-share dir); Sober's launcher reads these through the
# environment variables set in the launcher below.
RT_SHARE=$(ls -d /var/lib/flatpak/runtime/org.gnome.Platform/x86_64/*/active/files/share 2>/dev/null | head -1)
if [ -n "$RT_SHARE" ]; then
  if [ -d "$RT_SHARE/alsa" ]; then
    mkdir -p /usr/share/alsa && cp -a "$RT_SHARE/alsa/." /usr/share/alsa/
  fi
  if [ -d "$RT_SHARE/runtime" ]; then
    mkdir -p /usr/share/runtime && cp -a "$RT_SHARE/runtime/." /usr/share/runtime/
  fi
fi

# ---------------------------------------------------------------------------
# 2b. Roblox (Sober) launchers. The image build installs Sober and overlays
#     its runtime libraries, so the app binary runs directly (flatpak's
#     sandbox cannot work in Codespaces). The menu launcher hands off to
#     the 'roblox' user (see 2a); the runner replicates the flatpak sandbox
#     environment the app expects (FLATPAK_ID, XDG dirs, etc.) and gives it
#     a session bus. IMPORTANT: Sober's anti-tamper additionally blocks ALL
#     containers/VMs by design - the UI starts, but the actual Roblox game
#     client is killed by Sober itself in any container. See README.
# ---------------------------------------------------------------------------
SOBER_BIN=/app/bin/sober
cat > "$BIN_DIR/roblox" <<'RB'
#!/bin/bash
# Roblox (Sober) - launched from the desktop menu or a terminal.
# Runs the app as the dedicated non-root user; the runner script has the
# full environment.
if [ ! -x /app/bin/sober ]; then
  echo "Roblox is not installed (run the container build/rebuild first)." >&2
  exit 1
fi
DISPLAY="${DISPLAY:-:1}"
export DISPLAY
# Grant the app user access to the X server (the desktop runs X as root;
# the app user cannot read the Xauthority file, so an xhost entry is used).
xhost "+SI:localuser:roblox" >/dev/null 2>&1 || true
exec sudo -u roblox env DISPLAY="$DISPLAY" /usr/local/bin/roblox-runner "$@"
RB
chmod +x "$BIN_DIR/roblox"

cat > "$BIN_DIR/roblox-runner" <<'RBR'
#!/bin/bash
# Runs as the 'roblox' user (never root - Sober refuses root). Replicates
# the flatpak sandbox environment: the app checks /proc/self/exe, the XDG
# dirs, FLATPAK_ID and friends, and only starts the client when they look
# like a real flatpak install.
set -e
RBX_UID=$(id -u)
export HOME=/home/roblox
export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR=/run/user/$RBX_UID
export FLATPAK_ID=org.vinegarhq.Sober
export FLATPAK_SANDBOX_DIR=/home/roblox/.var/app/org.vinegarhq.Sober/sandbox
export XDG_DATA_HOME=/home/roblox/.var/app/org.vinegarhq.Sober/data
export XDG_CONFIG_HOME=/home/roblox/.var/app/org.vinegarhq.Sober/config
export XDG_CACHE_HOME=/home/roblox/.var/app/org.vinegarhq.Sober/cache
export XDG_STATE_HOME=/home/roblox/.var/app/org.vinegarhq.Sober/.local/state
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=GNOME
export XDG_CONFIG_DIRS=/app/etc/xdg:/etc/xdg
export XDG_DATA_DIRS=/app/share:/usr/share:/usr/share/runtime/share:/run/host/user-share:/run/host/share
export ALSA_CONFIG_DIR=/usr/share/alsa
export ALSA_CONFIG_PATH=/usr/share/alsa/alsa-flatpak.conf
export AT_SPI_BUS_ADDRESS=unix:path=/run/user/$RBX_UID/at-spi/bus
export GI_TYPELIB_PATH=/app/lib/girepository-1.0
export GST_PLUGIN_SYSTEM_PATH=/app/lib/gstreamer-1.0:/usr/lib/extensions/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/codecs-extra/lib/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0
export __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS=/etc/egl/egl_external_platform.d:/usr/lib/x86_64-linux-gnu/GL/egl/egl_external_platform.d:/usr/share/egl/egl_external_platform.d
export container=flatpak
export LD_LIBRARY_PATH=
export PATH=/app/bin:/usr/bin
mkdir -p "$FLATPAK_SANDBOX_DIR" "$XDG_STATE_HOME"
exec dbus-run-session -- /app/bin/sober "$@"
RBR
chmod +x "$BIN_DIR/roblox-runner"

# Tuned config for a software-rendered desktop (no GPU): force OpenGL
# (llvmpipe) instead of Vulkan, keep HiDPI off, cap texture quality and
# grass, and let Sober pick the lowest-fidelity LODs. Only written when
# the user has no config yet - their settings always win.
SOBER_CFG="$HOMEDIR/.var/app/org.vinegarhq.Sober/config/sober/config.json"
if [ -x /app/bin/sober ] && [ ! -f "$SOBER_CFG" ]; then
  mkdir -p "$(dirname "$SOBER_CFG")"
  cat > "$SOBER_CFG" <<'JSON'
{
  "use_opengl": true,
  "enable_hidpi": false,
  "touch_mode": "off",
  "graphics_optimization_mode": "performance",
  "fflags": {
    "DFFlagTextureQualityOverrideEnabled": true,
    "DFIntTextureQualityOverride": 1,
    "FIntFRMMaxGrassDistance": 0
  }
}
JSON
  chown -R roblox:roblox "$DATA_DIR/private/sober" 2>/dev/null || true
fi

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
# 3b. Encrypted save profiles: password-protected archives that live on the
#     same desktop-data branch, so they sync between codespaces - including
#     codespaces run by different users. Only ciphertext is committed; the
#     passphrase is read from the terminal by 'age' and never stored, logged,
#     or sent anywhere. age derives the key with scrypt (N=2^18, ~256MB RAM
#     per guess, ~1s) - brute-forcing is infeasible for any long passphrase.
# ---------------------------------------------------------------------------
cat > "$BIN_DIR/desktop-profile" <<'PR'
#!/usr/bin/env bash
# Encrypted save profiles (see README). Only ciphertext is committed; the
# passphrase is read from the terminal by age and never stored or logged.
set -euo pipefail
DATA_DIR="${DESKTOP_DATA_DIR:-/workspaces/desktop-data}"
PROF_DIR="$DATA_DIR/profiles"
ACTION="${1:-}"
cd "$DATA_DIR"

# Fetch what other users pushed. list/restore read straight from the fetched
# state (FETCH_HEAD) - no merge, so local history and uncommitted files are
# never touched. save rebases on top of it only when a push collides.
fetch_origin() {
  git fetch -q origin desktop-data 2>/dev/null || true
}
profile_blob() { # <name> -> prints the encrypted profile from origin (or local)
  if git cat-file -e "FETCH_HEAD:profiles/$1.tar.gz.age" 2>/dev/null; then
    git show "FETCH_HEAD:profiles/$1.tar.gz.age"
  elif [ -f "$PROF_DIR/$1.tar.gz.age" ]; then
    cat "$PROF_DIR/$1.tar.gz.age"
  else
    return 1
  fi
}

case "$ACTION" in
  list)
    fetch_origin
    if git ls-tree -r --name-only FETCH_HEAD -- profiles/ 2>/dev/null | grep -q .; then
      git ls-tree -r --name-only FETCH_HEAD -- profiles/ | sed 's|.*/||;s|\.tar\.gz\.age$||'
    elif ls "$PROF_DIR"/*.age >/dev/null 2>&1; then
      ls -1 "$PROF_DIR"/*.age | sed 's|.*/||;s|\.tar\.gz\.age$||'
    else
      echo "(no encrypted profiles saved yet)"
    fi
    ;;
  save)
    if pgrep -x firefox >/dev/null; then
      echo "Firefox is running - close it first so the browser profile" >&2
      echo "(bookmarks, game saves) is archived consistently." >&2
      exit 1
    fi
    NAME="${2:-${GITHUB_USER:-}}"
    while [ -z "$NAME" ]; do read -rp "Profile name: " NAME; done
    # keep the name filesystem- and git-safe
    NAME=$(printf '%s' "$NAME" | tr -c 'a-zA-Z0-9._-' '-' | cut -c1-40)
    case "$NAME" in ""|"."|"..") echo "Invalid profile name." >&2; exit 1;; esac
    mkdir -p "$PROF_DIR"
    fetch_origin
    echo "This encrypts ~/Files plus the browser profile (bookmarks, game saves)"
    echo "and pushes ONLY the ciphertext to GitHub. Use a LONG passphrase - it is"
    echo "never stored anywhere; if you forget it, the profile is unrecoverable."
    TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
    # tar first, then encrypt to temp, then swap in atomically: a failure
    # anywhere leaves the previous saved profile untouched.
    tar -czf "$TMPD/profile.tar.gz" \
        --exclude='*/cache2' --exclude='*/startupCache' \
        --exclude='*/cache2/*' --exclude='*/startupCache/*' \
        files private/mozilla
    age -p -o "$TMPD/profile.tar.gz.age" "$TMPD/profile.tar.gz"
    mv -f "$TMPD/profile.tar.gz.age" "$PROF_DIR/$NAME.tar.gz.age"
    git add -A -- profiles/
    if ! git diff --cached --quiet -- profiles/; then
      git commit -qm "encrypted profile: $NAME ($(date -u +%Y-%m-%d_%H:%M))" -- profiles/
    fi
    if git push -q origin desktop-data 2>/tmp/profile-push.err; then
      echo "Profile '$NAME' saved (encrypted) and pushed to GitHub."
    else
      # Someone else saved first: replay our commit on top, keep local files.
      if git pull --rebase --autostash -q origin desktop-data 2>>/tmp/profile-push.err \
         && git push -q origin desktop-data 2>>/tmp/profile-push.err; then
        echo "Profile '$NAME' saved (encrypted) and pushed to GitHub."
      else
        echo "Push to GitHub FAILED:" >&2
        head -3 /tmp/profile-push.err >&2
        echo "The encrypted profile is committed locally - run this again later to retry." >&2
        exit 1
      fi
    fi
    ;;
  restore)
    if pgrep -x firefox >/dev/null; then
      echo "Firefox is running - close it first so the restored browser profile" >&2
      echo "is not overwritten by the live one." >&2
      exit 1
    fi
    NAME="${2:-}"
    fetch_origin
    if [ -z "$NAME" ]; then
      echo "Saved profiles:"
      "$0" list
      read -rp "Profile to restore: " NAME
    fi
    TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
    if ! profile_blob "$NAME" > "$TMPD/profile.tar.gz.age" 2>/dev/null; then
      echo "No profile '$NAME'. Try 'desktop-profile list'." >&2
      exit 1
    fi
    # age reads the passphrase from the terminal and writes nothing on a
    # wrong one, so a failed decrypt leaves the desktop untouched.
    if ! age -d -o "$TMPD/profile.tar.gz" "$TMPD/profile.tar.gz.age" 2>/tmp/profile-dec.err; then
      echo "Restore FAILED - wrong password or corrupted profile:" >&2
      grep -i "passphrase\|error" /tmp/profile-dec.err | head -1 >&2
      exit 1
    fi
    # Fully extract first; only a complete archive triggers the swap.
    mkdir -p "$TMPD/x"
    tar -xzf "$TMPD/profile.tar.gz" -C "$TMPD/x"
    # The profile REPLACES ~/Files and the browser profile (no mixing with
    # what is on this codespace). The previous state is kept locally.
    BK="$DATA_DIR/.pre-restore-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BK"
    [ -d files ] && mv files "$BK/files"
    [ -d private/mozilla ] && mv private/mozilla "$BK/private-mozilla"
    mkdir -p private
    # mv to the full target path: files/ was moved aside, so this is a rename
    mv "$TMPD/x/files" "$DATA_DIR/files"
    [ -d "$TMPD/x/private/mozilla" ] && mv "$TMPD/x/private/mozilla" "$DATA_DIR/private/mozilla"
    echo "Profile '$NAME' restored. Previous state kept in $BK (local only)."
    ;;
  *)
    echo "Usage: desktop-profile save [name]    encrypt ~/Files + browser data, push"
    echo "       desktop-profile restore [name]  decrypt a profile into this codespace"
    echo "       desktop-profile list            show saved profiles"
    exit 1
    ;;
esac
PR
chmod +x "$BIN_DIR/desktop-profile"

# ---------------------------------------------------------------------------
# 4. Desktop menu entries (managed block: replaced wholesale on every run,
#    so upgrades add entries without duplicating old ones)
# ---------------------------------------------------------------------------
MENU="$HOMEDIR/.fluxbox/menu"
# Codespaces' clone can be owned by a different uid after rebuilds; stop
# git's dubious-ownership check from breaking pulls on the working dir.
git config --global --add safe.directory "$REPO_DIR" 2>/dev/null || true
git config --global --add safe.directory /workspaces/appimage-codespace-test 2>/dev/null || true

if [ -f "$MENU" ]; then
  awk -v home="$HOMEDIR" -v fluxdir="$HOMEDIR/.fluxbox" '
    BEGIN {
      block = "# >>> desktop-apps >>>\n[exec] (Roblox) {roblox}\n[exec] (Run Program...) {fbrun}\n[exec] (Task Manager) {tilix -e htop}\n[exec] (Files) {nautilus " home "/Files}\n[exec] (Keyboard Shortcuts) {mousepad " fluxdir "/SHORTCUTS}\n[submenu] (Encrypted Profiles) {}\n[exec] (Save Profile) {tilix -t \"Save Profile\" -e desktop-profile save}\n[exec] (Restore Profile) {tilix -t \"Restore Profile\" -e desktop-profile restore}\n[exec] (List Profiles) {tilix -t \"Profiles\" -e desktop-profile list}\n[end]\n[exec] (Back Up Files) {tilix -e desktop-backup}\n[restart] (Apply Desktop Updates) {}\n# <<< desktop-apps <<<"
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
# --- dark taskbar theme ---
toolbar: flat gradient vertical
toolbar.color: rgb:28/28/3A
toolbar.colorTo: rgb:1C/1C/29
toolbar.textColor: rgb:C8/C8/D8
toolbar.bevelWidth: 1
toolbar.clock: flat solid
toolbar.clock.color: rgb:1E/1E/2C
toolbar.clock.textColor: rgb:9A/9A/B5
toolbar.workspace: parentrelative
toolbar.workspace.textColor: rgb:C0/C0/D4
toolbar.button: parentrelative
toolbar.button.picColor: rgb:9A/9A/B5
toolbar.button.pressed: parentrelative
toolbar.button.pressed.picColor: rgb:D0/D0/E0
toolbar.iconbar.empty: flat solid
toolbar.iconbar.empty.color: rgb:1E/1E/2C
toolbar.iconbar.focused: flat gradient vertical
toolbar.iconbar.focused.color: rgb:3E/3E/5A
toolbar.iconbar.focused.colorTo: rgb:2C/2C/42
toolbar.iconbar.focused.textColor: rgb:F0/F0/FA
toolbar.iconbar.focused.borderColor: rgb:62/62/94
toolbar.iconbar.focused.borderWidth: 1
toolbar.iconbar.unfocused: flat solid
toolbar.iconbar.unfocused.color: rgb:22/22/30
toolbar.iconbar.unfocused.textColor: rgb:85/85/9C
# --- dark root menu ---
menu.title: flat gradient vertical
menu.title.color: rgb:2E/2E/44
menu.title.colorTo: rgb:20/20/30
menu.title.textColor: rgb:D8/D8/E8
menu.frame: flat solid
menu.frame.color: rgb:24/24/33
menu.frame.textColor: rgb:C4/C4/D4
menu.frame.disableColor: rgb:5C/5C/6C
menu.hilite: flat solid
menu.hilite.color: rgb:3D/3D/5E
menu.hilite.textColor: rgb:EE/EE/F8
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
Mod1 grave :NextWindow {groups} (workspace=[current])
Mod1 Shift grave :PrevWindow {groups} (workspace=[current])
# Alt+1..4 jump straight to a workspace
Mod1 1 :Workspace 1
Mod1 2 :Workspace 2
Mod1 3 :Workspace 3
Mod1 4 :Workspace 4
# Ctrl+Alt+Delete opens the task manager, like a normal desktop
Control Mod1 Delete :ExecCommand tilix -e htop
# <<< desktop-keys <<<"
if [ ! -f "$KEYS" ]; then
  # First run: fluxbox would create this from /etc/X11/fluxbox/keys at first
  # start (postCreate runs before that); write that default plus our block.
  # Drop the stock Ctrl+Alt+Del :Exit binding (it would kill the desktop, and
  # a duplicate would make fluxbox reject our task-manager binding).
  grep -v '^Control Mod1 Delete' /etc/X11/fluxbox/keys > "$KEYS" 2>/dev/null || true
  [ -s "$KEYS" ] || printf 'OnDesktop Mouse3 :RootMenu\n' > "$KEYS"
  printf '%s\n' "$keys_block" >> "$KEYS"
elif ! grep -q '^# >>> desktop-keys >>>' "$KEYS"; then
  grep -v '^Control Mod1 Delete' "$KEYS" > "$KEYS.new" && mv "$KEYS.new" "$KEYS"
  printf '%s\n' "$keys_block" >> "$KEYS"
else
  awk '
    /^# >>> desktop-keys >>>/ { inb = 1; next }
    /^# <<< desktop-keys <<</ { inb = 0; next }
    inb { next }
    # drop any stock Ctrl+Alt+Del binding outside our block (see above)
    /^Control Mod1 Delete/ && !inb { next }
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

System
  Ctrl+Alt+Delete            task manager (htop; also in the menu)
DOC

# --- WebGL: the codespace has no GPU; Firefox renders WebGL in software
# (Mesa software rasterizer on the CPU). Force it on so blocklist entries
# for software renderers can not silently disable it. Written to every
# profile on each start; applied when Firefox next launches. ---
for prof in "$HOMEDIR"/.mozilla/firefox/*.default-release \
            "$HOMEDIR"/.mozilla/firefox/*.default; do
  [ -d "$prof" ] || continue
  # Managed prefs only: replace just our webgl lines, keep anything the
  # user authored in user.js.
  touch "$prof/user.js"
  # '|| true': grep -v exits 1 when it filters out every line (normal here).
  { grep -vF 'user_pref("webgl.force-enabled"' "$prof/user.js" \
      | grep -vF 'user_pref("webgl.disabled"'; } > "$prof/user.js.new" || true
  printf 'user_pref("webgl.force-enabled", true);\nuser_pref("webgl.disabled", false);\n' \
    >> "$prof/user.js.new"
  mv "$prof/user.js.new" "$prof/user.js"
done

# --- apply to a running desktop: this script can run after the desktop has
# already started (postStart). Restarting fluxbox re-reads init/keys/menu/
# overlay, keeps every window open, and takes under a second. ---
if pgrep -x fluxbox >/dev/null 2>&1; then
  DISPLAY="${DISPLAY:-:1}" fluxbox-remote restart >/dev/null 2>&1 || true
fi

echo "Setup complete - open the forwarded port 6080 in your browser."
