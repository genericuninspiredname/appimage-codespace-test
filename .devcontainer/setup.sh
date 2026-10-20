#!/usr/bin/env bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq xvfb fluxbox imagemagick x11-utils xdotool pulseaudio pulseaudio-utils \
  wget file unzip xz-utils bzip2 zstd ca-certificates xdg-utils \
  libgtk-3-0t64 libnss3 libasound2t64 libgbm1 libxss1 libsecret-1-0 \
  libglib2.0-0t64 libfuse2t64 libc6 libstdc++6 libgl1 libegl1 libopengl0 \
  libvulkan1 mesa-utils libdrm2 libxkbcommon0 2>/dev/null
apt-get clean
echo "setup done"
