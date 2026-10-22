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
#   roblox - Sober flatpak + its runtime library overlay (flatpak, python3)
#   steam  - official steam.deb + the i386 multilib GL stack
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
    roblox|steam|prism) ;;
    *) echo "ERROR: unknown OPTIONAL_APPS token '$token' (valid: roblox steam prism)" >&2; exit 1 ;;
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
# OPTIONAL: Steam. The official .deb (package 'steam-launcher') installs
# the client; the i386 GL stack below is what its software rendering
# needs. Steam needs the i386 multilib stack (its client is a 32-bit
# binary at heart); the architecture is added BEFORE the apt-get update
# that follows so one update covers both architectures. The client refuses
# to run as root, so setup.sh launches it as a dedicated 'steam' user
# (same pattern as the roblox user).
# ---------------------------------------------------------------------
if has_opt steam; then
  dpkg --add-architecture i386
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    libgl1-mesa-dri:i386 libgl1:i386
  curl -fsSL --retry 3 -o /tmp/steam.deb \
    https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
  apt-get install -y -qq /tmp/steam.deb
  rm -f /tmp/steam.deb
fi

# ---------------------------------------------------------------------
# OPTIONAL: Java for PrismLauncher/Minecraft instances (the AppImage
# bundles its own; this is the system fallback for instances requesting
# a system JRE).
# ---------------------------------------------------------------------
if has_opt prism; then
  apt-get install -y -qq --no-install-recommends openjdk-21-jre || \
    apt-get install -y -qq --no-install-recommends default-jre
fi

# ---------------------------------------------------------------------
# OPTIONAL: Roblox (Sober). Sober is a Flatpak that runs the Roblox
# Android client natively on Linux. Codespaces blocks the user/mount
# namespaces that flatpak's sandbox (bubblewrap) needs, so `flatpak run`
# can never work here - but the app itself runs fine if it can see the
# libraries it was built against. So: install the flatpak (which is just
# a file deploy), then overlay the GNOME runtime's library set (glibc
# 2.4x + friends) over /usr/lib/x86_64-linux-gnu via symlinks. glibc is
# backward compatible, so every Ubuntu binary keeps working; Sober's
# launcher, which is built against the runtime, now runs directly with
# no sandbox. This option also installs python3 for the overlay script;
# the desktop's own dependencies may install and use python
# independently of this option.
# ---------------------------------------------------------------------
if has_opt roblox; then
  apt-get install -y -qq --no-install-recommends flatpak python3
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  # The bwrap errors printed during install are expected (namespaces are
  # blocked in Codespaces); the deployment lands anyway - verify it and
  # never fail the image build from this section (see /var/log/sober-setup.log).
  # The overlay script is written to /usr/local/share and executed by setup.sh.
  SOBER_LOG=/var/log/sober-setup.log
  echo "=== Sober install ===" > "$SOBER_LOG"
  mkdir -p /usr/local/share
  cat > /usr/local/share/sober-overlay.py <<'PYEOF'
import os, glob, sys

def atomic_symlink(target, link):
    tmp = link + ".sober-new"
    if os.path.lexists(tmp):
        os.unlink(tmp)
    os.symlink(target, tmp)
    os.replace(tmp, link)  # atomic swap

# Runtime lib dirs (paths go through flatpak's 'active' symlinks, so
# flatpak updates flow through automatically)
candidates_rt = glob.glob("/var/lib/flatpak/runtime/org.gnome.Platform/x86_64/*/active/files/lib/x86_64-linux-gnu")
candidates_gl = glob.glob("/var/lib/flatpak/runtime/org.freedesktop.Platform.GL.default/x86_64/*/active/files/lib")
if not candidates_rt or not candidates_gl:
    sys.exit("ERROR: Sober runtime dirs not found - was the flatpak install successful?")
RT, GL = candidates_rt[0], candidates_gl[0]

dest = "/usr/lib/x86_64-linux-gnu"
# libdbus is excluded: its LIBDBUS_PRIVATE symbol versions are distro-
# specific, and Ubuntu's dbus tools (dbus-daemon, dbus-run-session - used
# by the desktop startup) break against the runtime's copy. Sober only
# needs the public libdbus ABI, which Ubuntu's provides.
EXCLUDE = ("libdbus-1",)
replaced = 0
# Replace ld.so LAST so the loader/libc pair never mismatches for long.
# All steps run inside this one process, back to back.
for srcdir in (RT, GL):
    for name in sorted(os.listdir(srcdir)):
        if name.startswith("ld-linux") or name == "ld.so":
            continue
        if name.startswith(EXCLUDE):
            continue
        src = os.path.join(srcdir, name)
        if os.path.isdir(src):
            # whole dirs from the GL extension: dri drivers, gbm, etc.
            dst = os.path.join(dest, name)
            if os.path.isdir(dst) and not os.path.islink(dst):
                import shutil
                shutil.rmtree(dst)
            atomic_symlink(src, dst)
            replaced += 1
        elif os.path.isfile(src) or os.path.islink(src):
            # real files and soname symlinks (they resolve in place)
            atomic_symlink(src, os.path.join(dest, name))
            replaced += 1

# The dynamic loader: must match the new libc, so swap it in the same pass.
for srcdir in (RT, GL):
    for name in os.listdir(srcdir):
        if name.startswith("ld-linux-x86-64"):
            atomic_symlink(os.path.join(srcdir, name), os.path.join(dest, name))
            replaced += 1

# Vulkan software renderer (lavapipe) ICD manifests, if present in the GL extension
for icddir in glob.glob("/var/lib/flatpak/runtime/org.freedesktop.Platform.GL.default/x86_64/*/active/files/vulkan/icd.d"):
    os.makedirs("/usr/share/vulkan/icd.d", exist_ok=True)
    for name in os.listdir(icddir):
        atomic_symlink(os.path.join(icddir, name), os.path.join("/usr/share/vulkan/icd.d", name))

# Fedora's TLS stack (the runtime's libcurl/openssl) looks for Fedora's CA
# bundle paths; point them at Ubuntu's certificates so downloads verify.
if os.path.exists("/etc/ssl/certs/ca-certificates.crt"):
    for p in ("/etc/pki/tls/certs/ca-bundle.crt",
              "/etc/pki/tls/certs/ca-bundle.trust.crt",
              "/etc/pki/tls/cert.pem",
              "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"):
        try:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            if not os.path.exists(p):
                atomic_symlink("/etc/ssl/certs/ca-certificates.crt", p)
        except Exception:
            pass

print("overlaid %d runtime libraries" % replaced)
PYEOF
  if flatpak install -y --noninteractive flathub org.vinegarhq.Sober >>"$SOBER_LOG" 2>&1; then
    echo "flatpak install: exit 0" >>"$SOBER_LOG"
  else
    echo "flatpak install: nonzero exit (trigger phase fails without namespaces - may still be deployed)" >>"$SOBER_LOG"
  fi
  if flatpak list 2>/dev/null | grep -qi "vinegarhq.Sober"; then
    echo "Sober flatpak deployed" >>"$SOBER_LOG"
    # The overlay itself runs from setup.sh on every start: devcontainer
    # features apt-install packages AFTER this build step and would
    # overwrite the overlaid files (e.g. libmount).
    echo "library overlay script: /usr/local/share/sober-overlay.py" >>"$SOBER_LOG"
    apt-mark hold libc6 >>"$SOBER_LOG" 2>&1 || true
  else
    echo "WARN: Sober flatpak did not deploy - Roblox will be missing" >>"$SOBER_LOG"
  fi
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
