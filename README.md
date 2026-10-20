# Browser Desktop (noVNC) in a Codespace

A one-click private Linux desktop that opens in your browser tab. Built with the
`desktop-lite` devcontainer feature (Fluxbox + TigerVNC + noVNC) on port 6080.

## What's preinstalled

- Helium browser (AppImage) — also wired to the "Web Browser" menu entry
- OBS Studio (AppImage)
- PulseAudio (via the "Start Audio" menu item — click it once per session)
- File manager, terminal, and text editor come with desktop-lite

## How to launch

1. Open this repo on GitHub → green **Code** button → **Codespaces** tab → create.
2. Wait for setup to finish (~5-10 min; it downloads the apps).
3. The desktop tab should open automatically. If not: **Ports** panel → port `6080` → open.
4. VNC password: `vscode`

## Cost notes

- You are billed for compute while the codespace is **running**, and for disk
  storage while it exists (even stopped). Stop it from the Codespaces list when
  done; delete it when you no longer need it at all.
- Default 2-core machine is fine for browsing; pick 4-core for smoother OBS use.

## Limitations

- Software rendering only (no GPU): normal apps are fine, video is sluggish.
- Audio works via PulseAudio (Start Audio menu item) but is not forwarded to
  your machine — it exists so apps like OBS have a sound device to capture.
- The desktop is a remote view, not a web app: your local devices (webcam,
  mic) are not available inside it.

## Adding more apps

Edit `.devcontainer/setup.sh` — add another `install_appimage <name> <url>` line
and a matching menu entry — then rebuild the container (Codespaces panel →
"Rebuild container").
