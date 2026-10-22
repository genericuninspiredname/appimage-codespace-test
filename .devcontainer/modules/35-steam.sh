#!/usr/bin/env bash
# 35-steam.sh - optional Steam + PrismLauncher setup.
# Ported from the steam-prismlauncher branch (sections 2c/2d of its setup.sh
# additions, commit 5c954c3) into the modular layout. Behavior unchanged.
# Uses: HOMEDIR DATA_DIR BIN_DIR (and link_dir from 10-persistence.sh).
# ---------------------------------------------------------------------------
# 2c. Steam. The client refuses to run as root (same reason as Sober), so it
#     gets the dedicated-user treatment. Its data dirs (~/.steam and the
#     game library) are linked into the persistent data dir - a game library
#     can be many GB and /workspaces survives container rebuilds. The
#     'private/' subtree is gitignored, so credentials and game files never
#     enter the backup repo.
# ---------------------------------------------------------------------------
STEAM_USER=steam
if ! id "$STEAM_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$STEAM_USER"
fi
STEAM_UID=$(id -u "$STEAM_USER")
mkdir -p /run/user/"$STEAM_UID"
chown "$STEAM_USER" /run/user/"$STEAM_UID" && chmod 700 /run/user/"$STEAM_UID"
mkdir -p "$DATA_DIR/private/steam-home"
link_dir "/home/$STEAM_USER/.steam"              "$DATA_DIR/private/steam-home/steam"
link_dir "/home/$STEAM_USER/.local/share/Steam"  "$DATA_DIR/private/steam-home/local-share-steam"
chown -R "$STEAM_USER:$STEAM_USER" "$DATA_DIR/private/steam-home"

cat > "$BIN_DIR/steam" <<'ST'
#!/bin/bash
# Steam - launched from the desktop menu or a terminal. The client refuses
# to run as root, so it runs as the dedicated 'steam' user (see setup.sh).
# -no-cef-sandbox: Codespaces blocks the user namespaces the embedded CEF
# sandbox needs, so steamwebhelper (the whole UI) only renders without it.
STEAM_USER=steam
if ! id "$STEAM_USER" >/dev/null 2>&1 || [ ! -x /usr/bin/steam ]; then
  echo "Steam is not installed (run the container build/rebuild first)." >&2
  exit 1
fi
DISPLAY="${DISPLAY:-:1}"
export DISPLAY
xhost "+SI:localuser:$STEAM_USER" >/dev/null 2>&1 || true
exec sudo -u "$STEAM_USER" env DISPLAY="$DISPLAY" HOME="/home/$STEAM_USER" \
  /usr/bin/steam -no-cef-sandbox "$@"
ST
chmod +x "$BIN_DIR/steam"

# ---------------------------------------------------------------------------
# 2d. PrismLauncher (Minecraft). Runs as the desktop user (Java has no
#     problem with that). Instances, accounts and settings live under
#     ~/.local/share/PrismLauncher, linked into the persistent data dir.
#     Playing Minecraft needs a Microsoft login - the launcher UI works
#     without one, but launching an instance does not.
# ---------------------------------------------------------------------------
link_dir "$HOMEDIR/.local/share/PrismLauncher" "$DATA_DIR/private/prism"

cat > "$BIN_DIR/prismlauncher" <<'PL'
#!/bin/bash
# PrismLauncher (Minecraft) - launched from the desktop menu or a terminal.
if [ ! -x /opt/apps/prismlauncher/AppRun ]; then
  echo "PrismLauncher is not installed (run the container build/rebuild first)." >&2
  exit 1
fi
exec /opt/apps/prismlauncher/AppRun "$@"
PL
chmod +x "$BIN_DIR/prismlauncher"
