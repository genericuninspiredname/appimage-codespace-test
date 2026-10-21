#!/usr/bin/env bash
# 30-roblox.sh - optional Roblox (Sober) setup.
# Split from setup.sh (sections 1b, 2a, 2b + Sober config); behavior unchanged.
# Steps that need the built image (flatpak app files, runtime overlay) are
# guarded on Sober being present; the dedicated user, persistence link and
# launchers are always (re)installed, as before.
# Uses: HOMEDIR DATA_DIR BIN_DIR.
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
