#!/usr/bin/env bash
set -e

# Codespaces blocks unshare/userns; skip the pkgforge AppImage namespaces
# check so Helium (and other pkgforge apps) launch without a dialog.
mkdir -p "$HOME/.cache"
touch "$HOME/.cache/.disable-namespaces-check"

# Add app shortcuts to the Fluxbox menu (menu is written once by desktop-lite)
MENU="$HOME/.fluxbox/menu"
if [ -f "$MENU" ] && ! grep -q "Helium Browser" "$MENU"; then
  awk '
    BEGIN { apps = "[exec] (Helium Browser) {/opt/apps/helium/AppRun --no-sandbox}\n[exec] (OBS Studio) {/opt/apps/obs/AppRun}\n[exec] (Start Audio) {pulseaudio -D --exit-idle-time=-1}\n[exec] (Volume Control) {pavucontrol}" }
    !done && /\[begin\]/ { print; print apps; done=1; next }
    { print }
  ' "$MENU" > "$MENU.new" && mv "$MENU.new" "$MENU"
fi

echo "Setup complete - open the forwarded port 6080 in your browser."
