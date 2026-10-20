# Browser Desktop in a Codespace — How to Use

A private, lightweight Linux desktop that opens in a browser tab. It runs in
your GitHub Codespace (Fluxbox desktop + TigerVNC + noVNC on port 6080) with
Firefox as the browser — much lighter than Chromium on CPU and memory, and it
renders cleanly on a software-rendered 2-core machine.

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

- **Right-click the desktop** to open the Fluxbox menu: Web Browser, File
  Manager, Text Editor, Terminal, **Run Program...**, plus **Files** (your
  persistent folder), **Keyboard Shortcuts**, and **Back Up Files**.
- **Taskbar** (bottom): workspace name and arrows on the left, running windows
  in the middle (click one to focus or restore it), window-switch arrows and
  the clock on the right. Scrolling the taskbar or the desktop also cycles
  windows/workspaces.
- **Workspaces:** 4 by default. Switch with the taskbar arrows, Ctrl+Alt+Left/
  Right, Alt+1..4, or scrolling the desktop.
- **Window switching:** Alt+Tab works with a native VNC client, but the browser
  or OS usually swallows it when you're in the noVNC tab — **Alt+`**
  (backtick) is an alternative that is usually not intercepted. The menu's
  **Keyboard Shortcuts** entry lists everything.
- **Resolution:** right-click → System → Set Resolution (the default is
  1280x800). Fewer pixels = snappier.
- **After a rebuild:** the desktop may have started before setup applied
  desktop tweaks — right-click → **Apply Desktop Updates** (or stop and start
  the codespace) to refresh the taskbar, wallpaper, and shortcuts without
  closing your windows.

## Files and persistence

**Where to save things:** the **Files** menu entry (or `~/Files` in a terminal)
opens your persistent folder. Everything you put there survives stopping,
starting, and even container rebuilds, because it lives under `/workspaces`,
which GitHub preserves across rebuilds (changes outside `/workspaces` are lost
on rebuild) ([GitHub Docs](https://docs.github.com/en/codespaces/developing-in-a-codespace/rebuilding-the-container-in-a-codespace)).

Browser bookmarks and settings persist the same way (Firefox's profile is
stored in the same persistent location), so a rebuild doesn't reset them.

**Backups (survive codespace deletion):** deleting the codespace deletes its
disk, including `/workspaces`. To keep your documents, click **Back Up Files**
in the menu — it commits `~/Files` to the private `desktop-data` branch of this
repo and pushes it to GitHub. A fresh codespace restores those files
automatically on creation. Backups include only your documents in `~/Files` —
browser profiles and credentials are deliberately never pushed.

**Editing files:** right-click → Text Editor (mousepad), or double-click files
in the Files window. Save with Ctrl+S — files are written directly to the
persistent folder.

**Large files:** videos and archives are excluded from backups (`.gitignore`);
they persist across rebuilds but not across codespace deletion.

## What to expect

- Rendering is software-only (no GPU). Firefox is a full browser on a
  CPU-rendered desktop — browsing is fine, video playback is watchable but not silky.
- **WebGL** is rendered in software by the CPU (software Mesa inside the
  Firefox AppImage — no GPU involved). Check with
  [get.webgl.org](https://get.webgl.org/): you should see the spinning cube.
  Note: the desktop runs at **24-bit color** (`VNC_RESOLUTION` in
  devcontainer.json is `1280x800x24`). Without the `x24` suffix the
  desktop-lite feature silently starts the VNC display at 16-bit color,
  which leaves Firefox with no usable GL visuals — games like PokéRogue
  then abort with "Cannot create WebGL context". The setup also
  force-enables WebGL in the Firefox profile (`user.js`:
  `webgl.force-enabled`) so blocklist entries for software renderers can't
  silently turn it off. Heavy 3D sites are still CPU-bound: on the 2-core
  machine they can be slow; a 4-core machine or a lower resolution helps.
- Firefox runs with its content-process sandbox disabled
  (`MOZ_DISABLE_CONTENT_SANDBOX=1`) because Codespaces blocks the kernel
  feature (user namespaces) it requires. Firefox shows an orange
  "security sandbox is disabled" banner about this — expected, not an error.
  Treat the codespace as semi-disposable; the blast radius of a browser
  exploit is this container.
- Your local webcam/mic are not available inside the desktop — it's a remote
  view, not a web app.

## Making it faster

- **Use a 4-core machine** (`-m standardLinux32gb` when creating, or change
  machine type on a stopped codespace). This is the single biggest speed-up;
  it burns your monthly hours at 2x rate.
- **Lower the resolution:** right-click → System → Set Resolution.
- **noVNC quality:** in the browser tab, open the noVNC sidebar and lower the
  quality setting — trades sharpness for responsiveness.
- Close the browser when not using the desktop; it's the heaviest app in the
  container.

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
- Deleting a codespace does not touch the repo — you can always create a new one
  (and **Back Up Files** restores your documents).
