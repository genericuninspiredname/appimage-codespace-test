# Browser Desktop in a Codespace — How to Use

A private Linux desktop that opens in a browser tab. It runs in your GitHub
Codespace (Fluxbox desktop + TigerVNC + noVNC on port 6080) with the Helium
browser and OBS Studio preinstalled.

## Start it

1. Open [the repo](https://github.com/genericuninspiredname/appimage-codespace-test) on GitHub.
2. Click the green **Code** button → **Codespaces** tab → **Create codespace on master**.
3. First creation builds the image (a few minutes). Later creations reuse the
   cached image and start fast.
4. When it's ready, a browser tab opens automatically with the desktop. If it
   doesn't: in the codespace editor, open the **Ports** panel (bottom), find
   port `6080` labeled "Desktop (browser)", and click the globe icon to open it.
5. Password: `vscode`

You can also do it from a terminal with the GitHub CLI:

```bash
gh codespace create -R genericuninspiredname/appimage-codespace-test   # add -m standardLinux32gb for 4-core
gh codespace list                                                       # get the name
gh codespace stop -c <name>     # stop (stops compute billing)
gh codespace delete -c <name>    # delete (frees disk storage billing too)
```

## Use the desktop

- **Right-click the desktop** to open the Fluxbox menu. Your apps are at the top:
  Helium Browser, OBS Studio, Start Audio, Volume Control.
- The taskbar at the bottom shows running apps; the desktop supports multiple workspaces.
- **Audio:** click **Start Audio** once per session (gives apps like OBS a sound
  device). Sound is not forwarded to your machine — it exists inside the codespace
  so apps can record/capture it.
- **Resolution:** right-click → System → Set Resolution, or change `VNC_RESOLUTION`
  in `.devcontainer/devcontainer.json` and rebuild.

## What to expect

- Rendering is software-only (no GPU). Browsing and normal apps are fine;
  video playback is watchable but not silky.
- The Helium "unsupported flag --no-sandbox" banner is expected: the codespace
  runs as root, which requires that flag.
- Your local webcam/mic are not available inside the desktop — it's a remote
  view, not a web app.
- Smoother experience: create the codespace with a 4-core machine
  (`-m standardLinux32gb`).

## Add more apps

Two ways:

1. **Permanent:** edit `install-apps.sh` — add another
   `install_appimage <name> <url> &` line (the release URL of any x86_64
   Linux AppImage) — then rebuild: Codespaces panel (bottom-left menu) →
   **Rebuild container**. The image build is cached, so only the first
   rebuild after a change is slow.
2. **Quick test:** download any AppImage in the codespace terminal, extract it
   (`./app.AppImage --appimage-extract`), and run `squashfs-root/AppRun`.

If a pkgforge AppImage shows a "user namespaces" message, it's already handled —
setup marks it disabled. Other AppImages may need
`touch ~/.cache/.disable-namespaces-check` too.

## Billing notes

- Billed for compute while **running**; disk storage counts while it exists
  (even stopped). Stop when done for the day; delete when done for good.
- Deleting a codespace does not touch the repo — you can always create a new one.
