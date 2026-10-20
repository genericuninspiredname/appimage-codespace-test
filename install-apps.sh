#!/usr/bin/env bash
set -e
install_appimage() {
  local name="$1" url="$2"
  # pkgforge AppImages extract to AppDir with squashfs-root as a symlink to it,
  # so extract inside a per-app temp dir and move the real directory out
  rm -rf "/opt/apps/$name" "/opt/apps/$name.tmp"
  mkdir -p "/opt/apps/$name.tmp"
  cd "/opt/apps/$name.tmp"
  curl -fsSL --retry 3 -o app.AppImage "$url"
  chmod +x app.AppImage
  ./app.AppImage --appimage-extract >/dev/null
  rm -f app.AppImage
  mv AppDir "/opt/apps/$name"
  cd /opt/apps && rm -rf "$name.tmp"
  echo "installed: $name"
}

mkdir -p /opt/apps
install_appimage firefox "https://github.com/pkgforge-dev/Firefox-AppImage/releases/download/158.0%402026-10-13_1791907872/Firefox-158.0-anylinux-x86_64.AppImage"
echo "apps installed"
