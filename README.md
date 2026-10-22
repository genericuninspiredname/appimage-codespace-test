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
- **Task manager:** right-click → **Task Manager** (or press
  **Ctrl+Alt+Delete**) opens `htop` in a terminal — CPU, memory, and
  processes, with F9 to kill a stuck app.
- **Resolution:** right-click → System → Set Resolution (the default is
  1024x640 — ~36% fewer pixels than the old 1280x800;
  bump it back up there if you want more room). Fewer pixels = snappier.
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
browser profiles and credentials are deliberately never pushed. If the push
fails, your documents stay committed locally and the tool says how many
commits are waiting — just run **Back Up Files** again later to retry (a
retry pushes everything that is pending). If it reports that the branch on
GitHub has commits this codespace lacks (backed up from another codespace),
it tells you the exact `git` commands to inspect and resolve that.

## Encrypted profiles (password-protected saves)

For data you want to keep **private from the repository** - and to carry saves
between codespaces run by **different users** - use the menu's **Encrypted
Profiles** submenu (or `desktop-profile` in a terminal):

- **Save Profile** packs `~/Files` and the browser profile (bookmarks, game
  saves - e.g. PokéRogue) as **two separate encrypted archives** — personal
  documents in one, browser secrets in the other — and pushes only the
  ciphertext to the same `desktop-data` branch. Use `--no-browser` to save
  documents only.
- **Restore Profile** decrypts a profile into the current codespace — from any
  codespace of this repo, by any user who knows the passphrase. It decrypts
  and **validates** the archives first (a wrong passphrase, a corrupted
  archive, or an archive that is not actually a profile is rejected with
  nothing changed), then asks for confirmation of the exact replacement plan
  (type `restore`; `--yes` skips the prompt for scripts). Only then does it
  replace local data — and a mid-restore failure rolls everything back.
  `--files-only` restores documents without browser secrets; `--browser-only`
  the reverse.
- Each profile is independent: `profiles/<name>.tar.gz.age` (documents) plus
  `profiles/<name>.browser.tar.gz.age` (browser), one passphrase each. The
  default profile name is your GitHub login, so different users don't
  collide. Older single archives (documents + browser in one) still restore
  — the tool notes when it uses one; saving it again splits it into the two
  parts.
- `desktop-profile status` lists profiles and how many commits are waiting to
  push; `desktop-profile push` retries a failed upload without creating a new
  profile.

How it protects you - and where its limits are:

- The passphrase is read from the terminal by `age` and never stored, logged,
  or transmitted - the repository only ever receives ciphertext.
- Keys are derived with scrypt (2^18 iterations, ~256 MB of RAM and ~1 second
  per guess), which makes offline guessing extremely expensive. That resistance
  only holds if the passphrase is strong: use a long passphrase (think a
  sentence, not a word). A weak passphrase can still be guessed; a forgotten
  one cannot be recovered by anyone.
- Firefox must be closed for save/restore (the tool checks and tells you), so
  browser data is archived consistently.
- Trust boundaries to be aware of: the scripts in this repo run inside your
  codespace, so a malicious repo change (or anyone administering the running
  container) could capture a passphrase or read decrypted data - this feature
  protects data *at rest in Git*, not from the repo's own code. Writers with
  push access can also delete or replace saved profiles (git history keeps old
  copies). Saving requires write access to the repo; restoring works for
  anyone who can read it and has the passphrase.

**What about apps?** AppImages the repo installs (Firefox, etc.) are pinned in
`install-apps.sh` and reinstall automatically on rebuild, so they don't need
saving. Anything you download yourself is saved **if you keep it in `~/Files`**
(that folder is part of every encrypted profile). Apps installed system-wide
(via `apt`, or dropped outside `/workspaces`) are not part of profiles.

Note: the plain **Back Up Files** path commits `~/Files` **unencrypted** -
convenient, but readable by anyone with access to the repo (and whatever it
backed up earlier stays in the branch history). Use encrypted profiles for
anything sensitive. Restoring a profile **replaces** `~/Files` and the browser
profile (the previous state is kept in a local `.pre-restore-*` folder inside
the data dir, which is never pushed; if a replace step fails mid-way, the
tool rolls everything back to that state).

**Retention and cleanup:** pre-restore backups pile up silently, so only the 3
most recent `.pre-restore-*` folders are kept — each restore prunes the older
ones and says so. Change the number with `DESKTOP_KEEP_PRE_RESTORE` in the
codespace's environment. Two things are intentionally **not** cleaned up
automatically: the `desktop-data` branch keeps every version ever backed up
(that is what makes restores possible — but it also means deleted documents
stay in the git history; sensitive material belongs in encrypted profiles),
and old encrypted profiles are kept until you delete them yourself (`git rm`
the file in `/workspaces/desktop-data/profiles` and push).

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
  devcontainer.json is `1024x640x24`). Without the `x24` suffix the
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

## Roblox

**Status: blocked by Sober itself — the game client cannot run in any
container.** Roblox is **optional** (opt-in via the `roblox` token of the
`OPTIONAL_APPS` build arg — see [Core vs optional applications](#core-vs-optional-applications-image-size));
when enabled, the desktop ships it via
[Sober](https://github.com/vinegarhq/sober) (the standard Linux Roblox
runtime — it runs the Android client natively), and the launcher gets the
app as far as it can go inside a Codespace: it runs as a dedicated non-root
user with the Flatpak environment replicated, the window opens and the
onboarding UI starts — then Sober's built-in anti-tamper kills the actual
Roblox game client.

This is not a bug in this repo and cannot be fixed here:

- Sober's `libloader.so` (a closed-source anti-tamper layer) validates its
  environment and deliberately crashes (a `UD2` trap with "FATAL:
  Unrecognized Instruction") in **any** container or VM. Verified in this
  Codespace **and** in an independent unprivileged container with a real
  Flatpak sandbox, non-root user, no Docker seccomp filter, untraced —
  same crash.
- The Sober maintainers confirm this is intentional: crashes in "a virtual
  machine, container, or anything else designed to automate gameplay" are
  [expected behavior](https://github.com/vinegarhq/sober/issues/2475).
- The exact check lives in obfuscated code and has not been publicly
  identified; the game child also refuses to run as root (fixed here by the
  dedicated `roblox` user) and anti-debug is built in (it `ptrace`s itself
  to its supervisor, blocking debuggers).

What still works: the launcher, the Sober window, and the onboarding UI.
If Sober ever drops or relaxes the container check, this setup should work
as originally intended — everything else (environment, user, display,
persistence) is in place. Alternatives while it is blocked:

- run Roblox on a real (non-container) Linux machine with Sober, or on
  Windows/macOS/mobile;
- a cloud gaming/streaming service (now.gg works from the desktop's
  Firefox but has ads and was rejected for this repo);
- a full VM with KVM elsewhere — note Codespaces has no `/dev/kvm`, and
  QEMU without KVM is far too slow for a 3D game, so a VM inside a
  Codespace is not viable.

- **Launch it:** right-click the desktop → **Roblox** (or run `roblox` in a
  terminal). It runs as the dedicated `roblox` user (never root — Sober
  refuses root), with the Flatpak sandbox environment replicated and its
  own D-Bus session.
- **Data persistence:** the Sober data dir
  (`/home/roblox/.var/app/org.vinegarhq.Sober`) is linked into the
  persistent `/workspaces/desktop-data` area, so any state survives
  rebuilds.
- **Sound:** the browser tab streams video only, so Roblox plays silently
  (audio isn't carried through noVNC).

Technical note: Sober is a Flatpak, but Codespaces blocks the kernel
namespaces its sandbox needs — so the image installs the flatpak, overlays
its runtime libraries (glibc included) onto the system, mirrors the app
tree to a real `/app` directory (the anti-tamper checks `/proc/self/exe`),
and the launcher runs the app binary directly as the `roblox` user with the
flatpak environment variables set. If Sober ever needs a manual config
change, the file is
`/home/roblox/.var/app/org.vinegarhq.Sober/config/sober/config.json`
(delete it to reset to defaults).

## Steam

**Status: blocked inside Codespaces by Steam itself — the client requires
user namespaces, which Codespaces blocks.** Steam is **optional** (opt-in
via the `steam` token of `OPTIONAL_APPS` — see
[Core vs optional applications](#core-vs-optional-applications-image-size));
when enabled it is preinstalled (official
`steam.deb` plus the i386 multilib stack) and everything around the client
is in place, but launching it inside a Codespace shows Steam's own error
dialog: "Steam now requires user namespaces to be enabled" (the same
kernel restriction that blocks Flatpak sandboxes here — see the Roblox
section). No workaround was found or verified in this repo.

- **Launch it:** right-click the desktop → **Steam** (or run `steam` in a
  terminal). Inside a Codespace you will see the namespace error dialog.
  In the container sandbox where the steam branch was developed (user
  namespaces allowed), the client and sign-in window did render; that
  result was not re-verified here.
- **Verified in this Codespace:** the install (i386 stack + `steam.deb`),
the dedicated non-root `steam` user, the launcher wrapper and the persistent
home (`~/.steam` for the `steam` user, including the game library, linked
into the desktop-data area so installs and logins survive rebuilds). The
client runtime itself was not verified here (it failed at the namespace
check; its interactive dependency prompt was dismissed manually during
testing).

## Minecraft (PrismLauncher)

[PrismLauncher](https://prismlauncher.org) is **optional** (opt-in via the
`prism` token of `OPTIONAL_APPS` — see
[Core vs optional applications](#core-vs-optional-applications-image-size));
when enabled it is preinstalled (AppImage,
extracted to `/opt/apps/prismlauncher`). Its setup wizard and main window
are verified working in the container; playing Minecraft additionally
requires a Microsoft account sign-in.

- **Launch it:** right-click the desktop → **Prism Launcher** (or run
  `prismlauncher` in a terminal).
- **First run:** the Quick Setup wizard walks through language and Java
  detection, then asks for a Microsoft account. Playing Minecraft requires
  being signed in — the launcher UI works without one, but launching an
  instance does not.
- **Instances:** create one with **Add Instance** (pick a Minecraft
  version — modern versions need Java 21+, which the image provides as a
  system fallback; the launcher also downloads its own Java per instance).

Minecraft renders on software rendering (llvmpipe supports the GL 3.2+
core profile modern versions need); actual gameplay performance on the
2-core machine class was not measured in this repo. The launcher data
(`~/.local/share/PrismLauncher` — instances, accounts, settings) is linked
into the persistent desktop-data area and survives rebuilds.

## Core vs optional applications (image size)

The image build installs only the **core** applications by default:
Firefox, the system software-OpenGL (llvmpipe) stack used for WebGL
rendering, `htop` (Task Manager), and `age` (encrypted-profile backups).
The desktop itself (Fluxbox, VNC, noVNC, file manager, editor, terminal)
comes from the `desktop-lite` feature.

Everything else is **optional** and no longer installed by default —
Roblox/Sober, Steam, and PrismLauncher/Minecraft are games most users of
this browser desktop don't need, and together with their dependencies
(the Sober flatpak's GNOME runtime, the Steam i386 multilib stack, the
system Java fallback) they made up the bulk of the image:

| App | token | What the token installs |
|-----|-------|--------------------------|
| Roblox (Sober) | `roblox` | Sober flatpak + GNOME runtime, library-overlay script (also `flatpak`, `python3`) |
| Steam | `steam` | official `steam.deb` + i386 multilib GL stack |
| Minecraft | `prism` | PrismLauncher AppImage + `openjdk-21-jre` fallback |

**To opt in:** edit `.devcontainer/devcontainer.json`, set the
`OPTIONAL_APPS` build arg to a space-separated list of tokens (e.g.
`"roblox steam prism"`), then rebuild the container (Codespaces menu →
**Rebuild container**). Restarting is not enough — the list is applied at
image-build time. Unknown tokens fail the build with a clear error.

The desktop UI is unchanged either way: menu entries and launchers for
optional apps always exist, and print a "not installed" hint when the
app files are absent. Measured size/build-time impact is recorded in
`CHANGES-perf.md`.

## Making it faster

- **Use a 4-core machine** (`-m standardLinux32gb` when creating, or change
  machine type on a stopped codespace). This is the single biggest speed-up;
  it burns your monthly hours at 2x rate.
- **Lower the resolution:** right-click → System → Set Resolution.
- **noVNC quality:** in the browser tab, open the noVNC sidebar and lower the
  quality setting — trades sharpness for responsiveness.
- Close the browser when not using the desktop; it's the heaviest app in the
  container.

**Resource budget** (measured on a 2-core codespace): the desktop itself is
lean — Fluxbox ~12 MB, the VNC server ~36 MB, noVNC's websockify ~33 MB
(~80 MB total for the whole desktop, before any apps). The wallpaper is a
20 KB PNG and the taskbar theme adds no measurable memory. Firefox under
software WebGL is the big one (several hundred MB with a few tabs open,
more with games like PokéRogue running) — the Task Manager (Ctrl+Alt+Delete)
or **System Stats** (`desktop-stats` in a terminal) shows you where the
memory actually goes.

## Startup speed and credit controls

Startup is split so that a plain stop→start is cheap, while expensive work
runs only when it can actually change something:

- **Once per codespace** (`postCreateCommand` → first-start): the
  first-start hooks, gated on the `.first-start-complete` marker.
- **Once per container lifetime** (startup stamps in
  `/var/lib/desktop-startup-stamps/`, wiped automatically by a rebuild):
  the Sober library overlay, the `/app` hardlink tree, the runtime-share
  copies, and the recursive `chown` over the Sober/Steam data dirs. A
  stop→start skips all of it; a rebuild re-runs it because a rebuild
  recreates that state from the image.
- **Every start** (`postStartCommand` → normal-start): only cheap,
  idempotent work — symlinks, launchers, menu/config managed blocks,
  restoring the desktop settings.

The stamp records a hash of its inputs (the module, the overlay script,
the flatpak commit ids), so editing any of them re-runs that work exactly
once more. To force everything to re-run on the next start:
`rm -rf /var/lib/desktop-startup-stamps` (or just rebuild).

`setup.sh` prints a per-module timing line on every run, so you can see
what a start actually costs.

**Idle check:** the menu's **Idle Check** (or `desktop-idle` in a terminal)
shows how long the desktop has had no mouse/keyboard input (via
`xprintidle`), how long terminal sessions have been idle, which desktop
apps are running, and the stop/delete commands — a read-only reminder,
it never stops anything itself.

**Diagnostics:** **System Stats** (or `desktop-stats`) prints a one-shot
CPU/memory snapshot: load, memory, swap, and the top processes by memory.

## Stop or delete the codespace

Codespaces bills **compute while running** and **disk storage while the
codespace exists** (even stopped). The idle timeout (Settings →
[Codespaces settings](https://github.com/settings/codespaces) → *Idle
timeout*, default 30 minutes) stops the machine automatically when you
walk away — set it lower to save credits.

**Stop** (ends compute billing, keeps the disk and storage billing):

- Web UI: [github.com/codespaces](https://github.com/codespaces) → the `···`
  menu on your codespace → **Stop codespace**; or from the editor's
  bottom-left menu → **Stop codespace**.
- CLI: `gh codespace stop -c <name>` (see `gh codespace list` for names).

**Delete** (ends compute AND storage billing; the disk, including
`/workspaces`, is gone — run **Back Up Files** first if you want your
documents):

- Web UI: [github.com/codespaces](https://github.com/codespaces) → the `···`
  menu → **Delete**.
- CLI: `gh codespace delete -c <name>`.

Deleting a codespace does not touch the repo — you can always create a new
one (and **Back Up Files** restores your documents).

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
  (even stopped). Stop when done for the day; delete when done for good —
  see [Stop or delete the codespace](#stop-or-delete-the-codespace) for
  the exact steps.
- Deleting a codespace does not touch the repo — you can always create a new one
  (and **Back Up Files** restores your documents).

## Repository layout (setup architecture)

`.devcontainer/setup.sh` is only a **coordinator**: it sets up the shared
environment, then sources the modules in `.devcontainer/modules/` in
lexical order:

| Module | Responsibility |
|--------|----------------|
| `05-startup-gates.sh` | Startup stamps: skip expensive work that already ran this container lifetime |
| `10-persistence.sh` | Persistent data dir, home symlinks, `desktop-backup` |
| `20-browser.sh` | Browser launcher, WebGL prefs, namespaces-check flag |
| `30-roblox.sh` | Optional Roblox/Sober setup (image-dependent steps guarded; user, links and launchers always installed) |
| `40-profiles.sh` | Encrypted save profiles (`desktop-profile`) |
| `50-menu.sh` | Fluxbox desktop menu entries |
| `60-fluxbox.sh` | Wallpaper, init, style overlay, keys, shortcuts |
| `70-diagnostics.sh` | git safe.directory fix, reapply to a running desktop |
| `80-perf-tools.sh` | `desktop-stats` (CPU/memory) and `desktop-idle` (inactivity check) |

After the modules it runs **lifecycle hooks** (see
`.devcontainer/hooks/README.md`):

- `hooks/first-start.d/` — once per codespace (creation)
- `hooks/normal-start.d/` — every start, including after rebuilds

Codespaces passes the mode explicitly (`postCreateCommand` →
`first-start`, `postStartCommand` → `normal-start`); a manual
`bash .devcontainer/setup.sh` infers it from the persisted marker
`$DATA_DIR/.first-start-complete`.

**Feature branches:** add a new numbered module or a hook script instead
of editing existing files — that is the whole point of this layout, it
keeps merges conflict-free. `tests/idempotence-test.sh` verifies setup
is safe to run repeatedly; run it after changing anything here.
