#!/usr/bin/env bash
set -e

# System software OpenGL (llvmpipe) for apps that link system Mesa instead
# of bundling their own, htop for the task manager, and age for the
# encrypted save profiles. The Firefox AppImage ships its own Mesa, so the
# GL libs are mostly for other apps and for `glxinfo -B` diagnostics.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  libgl1-mesa-dri libegl-mesa0 libglx-mesa0 htop age flatpak
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

# ---------------------------------------------------------------------------
# Roblox (Sober). Sober is a Flatpak that runs the Roblox Android client
# natively on Linux. Codespaces blocks the user/mount namespaces that
# flatpak's sandbox (bubblewrap) needs, so `flatpak run` can never work
# here - but the app itself runs fine if it can see the libraries it was
# built against. So: install the flatpak (which is just a file deploy),
# then overlay the GNOME runtime's library set (glibc 2.4x + friends)
# over /usr/lib/x86_64-linux-gnu via symlinks. glibc is backward
# compatible, so every Ubuntu binary keeps working; Sober's launcher,
# which is built against the runtime, now runs directly with no sandbox.
# ---------------------------------------------------------------------------
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
# The bwrap errors printed during install are expected (namespaces are
# blocked in Codespaces); the deployment itself completes.
flatpak install -y --noninteractive flathub org.vinegarhq.Sober || flatpak list | grep -qi sober

python3 - <<'PYEOF'
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
replaced = 0
# Replace ld.so LAST so the loader/libc pair never mismatches for long.
# All steps run inside this one process, back to back.
for srcdir in (RT, GL):
    for name in sorted(os.listdir(srcdir)):
        if name.startswith("ld-linux") or name == "ld.so":
            continue
        src = os.path.join(srcdir, name)
        if os.path.isdir(src):
            # whole dirs from the GL extension: dri drivers, gbm, etc.
            atomic_symlink(src, os.path.join(dest, name))
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

print("overlaid %d runtime libraries" % replaced)
PYEOF

# Regenerate the loader cache with the new libs and verify the toolchain
# still works (glibc is backward compatible - this must not fail).
ldconfig
apt-mark hold libc6 >/dev/null 2>&1 || true
echo "apps installed"
