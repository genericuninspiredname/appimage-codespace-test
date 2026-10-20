#!/usr/bin/env bash
set -e

# System software OpenGL (llvmpipe) for apps that link system Mesa instead
# of bundling their own, htop for the task manager, and age for the
# encrypted save profiles. The Firefox AppImage ships its own Mesa, so the
# GL libs are mostly for other apps and for `glxinfo -B` diagnostics.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  libgl1-mesa-dri libegl-mesa0 libglx-mesa0 htop age
rm -rf /var/lib/apt/lists/*

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
