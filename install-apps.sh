#!/usr/bin/env bash
set -e

# Core vs optional applications.
#
# CORE (always installed): Firefox AppImage, the system software-OpenGL
# (llvmpipe) stack for apps that link system Mesa (Firefox ships its own),
# htop for the task manager, and age for the encrypted save profiles /
# backup tools. Desktop, D-Bus, fonts, file manager, editor and terminal
# come from the desktop-lite devcontainer feature, not from this script.
#
# OPTIONAL (opt-in via OPTIONAL_APPS, a space-separated list of tokens):
#   prism  - PrismLauncher AppImage + openjdk-21-jre fallback
# Set via the OPTIONAL_APPS Docker build arg (see devcontainer.json);
# changing it requires a container rebuild. Invalid tokens fail the build.
# The desktop menu is unchanged either way: the launchers for optional apps
# exist regardless and print a "not installed" hint when the app is absent.
export DEBIAN_FRONTEND=noninteractive

OPTIONAL_APPS="${OPTIONAL_APPS:-}"

has_opt() { case " $OPTIONAL_APPS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

for token in $OPTIONAL_APPS; do
  case "$token" in
    prism) ;;
    *) echo "ERROR: unknown OPTIONAL_APPS token '$token' (valid: prism)" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------
# Core packages. System software OpenGL (llvmpipe) for apps that link
# system Mesa instead of bundling their own, htop for the task manager,
# and age for the encrypted save profiles. The Firefox AppImage ships its
# own Mesa, so the GL libs are mostly for other apps and for `glxinfo -B`
# diagnostics.
# ---------------------------------------------------------------------
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  libgl1-mesa-dri libegl-mesa0 libglx-mesa0 htop age


# ---------------------------------------------------------------------
# OPTIONAL: Java for PrismLauncher/Minecraft instances (the AppImage
# bundles its own; this is the system fallback for instances requesting
# a system JRE).
# ---------------------------------------------------------------------
if has_opt prism; then
  apt-get install -y -qq --no-install-recommends openjdk-21-jre || \
    apt-get install -y -qq --no-install-recommends default-jre
fi


# Package caches and lists are removed in this same layer so they never
# enter the image history.
apt-get clean
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

# ---------------------------------------------------------------------
# CORE: Firefox.
# ---------------------------------------------------------------------
install_appimage firefox "https://github.com/pkgforge-dev/Firefox-AppImage/releases/download/158.0%402026-10-13_1791907872/Firefox-158.0-anylinux-x86_64.AppImage"

# ---------------------------------------------------------------------
# OPTIONAL: PrismLauncher (Minecraft). Its AppImage extracts to
# squashfs-root (standard AppImage layout) rather than pkgforge's AppDir,
# so it gets its own extractor. Runs fine as the desktop user; instances
# live under ~/.local/share/PrismLauncher which setup.sh links into the
# persistent data dir. Java: the AppImage bundles what it needs, and
# openjdk-21 is installed system-wide as a fallback for instances that
# want a system JRE (see the prism option above).
# ---------------------------------------------------------------------
install_appimage_sqfs() {
  local name="$1" url="$2"
  rm -rf "/opt/apps/$name" "/opt/apps/$name.tmp"
  mkdir -p "/opt/apps/$name.tmp"
  cd "/opt/apps/$name.tmp"
  curl -fsSL --retry 3 -o app.AppImage "$url"
  chmod +x app.AppImage
  ./app.AppImage --appimage-extract >/dev/null
  rm -f app.AppImage
  mv squashfs-root "/opt/apps/$name"
  cd /opt/apps && rm -rf "$name.tmp"
  echo "installed: $name"
}

if has_opt prism; then
  # Resolve the PrismLauncher version at image-build time: fetch the latest
  # release tag from the GitHub API when available, falling back to 11.1.1.
  # NOTE: this is NOT a pin - a rebuild can pick up a newer release without
  # a change to this file. To truly pin a version, hardcode it below.
  PRISM_VER=$(curl -fsSL --retry 3 \
    https://api.github.com/repos/PrismLauncher/PrismLauncher/releases/latest \
    | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
  [ -n "$PRISM_VER" ] || PRISM_VER="11.1.1"
  install_appimage_sqfs prismlauncher \
    "https://github.com/PrismLauncher/PrismLauncher/releases/download/${PRISM_VER}/PrismLauncher-Linux-x86_64.AppImage"
fi

echo "apps installed (optional: ${OPTIONAL_APPS:-none})"
