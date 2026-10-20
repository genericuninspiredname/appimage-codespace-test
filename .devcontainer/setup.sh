#!/usr/bin/env bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "==> Installing audio support + fonts"
apt-get update -qq
apt-get install -y -qq pulseaudio pavucontrol fonts-noto-cjk ffmpeg >/dev/null
apt-get clean

# --- helper: install an AppImage into /opt/apps/<name> ---
install_appimage() {
  local name="$1" url="$2"
  echo "==> Installing $name"
  mkdir -p /opt/apps
  # pkgforge AppImages extract to AppDir with squashfs-root as a symlink to it,
  # so extract inside a temp dir and move the real directory out
  rm -rf "/opt/apps/$name" /opt/apps/"$name.tmp"
  mkdir -p "/opt/apps/$name.tmp"
  cd "/opt/apps/$name.tmp"
  curl -sL --retry 3 -o app.AppImage "$url"
  chmod +x app.AppImage
  ./app.AppImage --appimage-extract >/dev/null
  rm -f app.AppImage
  mv AppDir "/opt/apps/$name"
  cd /opt/apps && rm -rf "$name.tmp"
}

install_appimage helium "https://github.com/pkgforge-dev/Helium-Browser-AppImage-Enhanced/releases/download/0.19.2.1%402026-10-12_1791822299/Helium-0.19.2.1-anylinux-x86_64.AppImage"
install_appimage obs "https://github.com/pkgforge-dev/OBS-Studio-AppImage/releases/download/32.2.2-1%402026-10-01_1790876050/OBS_Studio-32.2.2-1-anylinux-x86_64.AppImage"

# Make the desktop-lite "Web Browser" menu entry open Helium
ln -sf /opt/apps/helium/AppRun /usr/local/bin/x-www-browser

# Add app shortcuts to the Fluxbox menu (menu is created once by desktop-lite)
MENU="$HOME/.fluxbox/menu"
if [ -f "$MENU" ] && ! grep -q "Helium Browser" "$MENU"; then
  awk '
    BEGIN { apps = "[exec] (Helium Browser) {/opt/apps/helium/AppRun --no-sandbox}\n[exec] (OBS Studio) {/opt/apps/obs/AppRun}\n[exec] (Start Audio) {pulseaudio -D --exit-idle-time=-1}\n[exec] (Volume Control) {pavucontrol}" }
    !done && /\[begin\]/ { print; print apps; done=1; next }
    { print }
  ' "$MENU" > "$MENU.new" && mv "$MENU.new" "$MENU"
fi

echo "==> Setup complete. Open the forwarded port 6080 in your browser to use the desktop."
