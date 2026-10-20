#!/usr/bin/env bash
set -e
install_appimage() {
  local name="$1" url="$2"
  # pkgforge AppImages extract to AppDir with squashfs-root as a symlink to it,
  # so extract inside a per-app temp dir and move the real directory out
  rm -rf "/opt/apps/$name" "/opt/apps/$name.tmp"
  mkdir -p "/opt/apps/$name.tmp"
  cd "/opt/apps/$name.tmp"
  curl -sL --retry 3 -o app.AppImage "$url"
  chmod +x app.AppImage
  ./app.AppImage --appimage-extract >/dev/null
  rm -f app.AppImage
  mv AppDir "/opt/apps/$name"
  cd /opt/apps && rm -rf "$name.tmp"
  echo "installed: $name"
}

mkdir -p /opt/apps
install_appimage helium "https://github.com/pkgforge-dev/Helium-Browser-AppImage-Enhanced/releases/download/0.19.2.1%402026-10-12_1791822299/Helium-0.19.2.1-anylinux-x86_64.AppImage" &
install_appimage obs "https://github.com/pkgforge-dev/OBS-Studio-AppImage/releases/download/32.2.2-1%402026-10-01_1790876050/OBS_Studio-32.2.2-1-anylinux-x86_64.AppImage" &
wait

# Make the desktop-lite "Web Browser" menu entry open Helium
ln -sf /opt/apps/helium/AppRun /usr/local/bin/x-www-browser
echo "apps installed"
