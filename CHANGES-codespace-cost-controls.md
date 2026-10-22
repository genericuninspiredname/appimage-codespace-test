# CHANGES — perf/codespace-cost-controls: startup speed and credit controls

Branch: `perf/codespace-cost-controls` (from master `d67ee4c`)
Goal: reduce Codespaces startup time and monthly credit usage.

## What changed

### Expensive setup no longer repeats on every start

New module `.devcontainer/modules/05-startup-gates.sh` provides small
stamp helpers (`stamp_changed` / `stamp_done` / `mod_hash`). Stamps live in
`/var/lib/desktop-startup-stamps/` (override: `DESKTOP_STAMP_DIR`) — a
directory that a plain stop→start keeps but a container rebuild wipes, which
is exactly the lifetime of the state they guard. Each stamp records a hash
of its inputs (the module file, the overlay script, the relevant flatpak
commit id), so changing any input re-runs that work exactly once more.

Gated sections (behavior on a rebuild is unchanged — they still run):

- `30-roblox.sh`: Sober runtime library overlay (+ `ldconfig`), the `/app`
  hardlink tree rebuild, the runtime-share (ALSA/runtime) copies, and the
  recursive `chown` over the Sober data dir.
- `35-steam.sh`: the recursive `chown` over the Steam home/game library.

A plain start now prints e.g. `Sober library overlay already current -
skipped.` and skips the work; the per-module timing line shows the effect.

### Startup timing (coordinator)

`.devcontainer/setup.sh` now measures each module and prints one summary
line per run (`Setup timing: mode=... modules=...ms ...`), so startup cost
is visible and regressions are caught early.

### Lower default resolution (WebGL preserved)

`.devcontainer/devcontainer.json`: `VNC_RESOLUTION` `1280x800x24` →
`1024x640x24`. Depth stays 24-bit, which is what keeps Firefox's software
WebGL visuals working (see README); only the pixel count dropped, so the
software-rendered desktop does ~40% less pixel work per frame.

### CPU/memory diagnostic + idle check

New module `.devcontainer/modules/80-perf-tools.sh` installs two small
commands (also in the Fluxbox menu):

- `desktop-stats` — one-shot CPU/memory snapshot: load, memory, swap, top
  processes by RSS.
- `desktop-idle` — read-only inactivity check: terminal-session idle times,
  which desktop apps are running, the idle-timeout reminder, and the exact
  `gh codespace stop` / `gh codespace delete` commands.

### Documentation

- README: new sections "Startup speed and credit controls" and
  "Stop or delete the codespace" (web UI + CLI steps for both, idle-timeout
  setting, storage-vs-compute billing, back-up-before-delete warning);
  resolution references updated; module table updated.
- Desktop features are unchanged: menu entries only gained the two new
  items; nothing was removed.

### Review hardening (second pass)

- Stamp inputs now hash the actual deployed flatpak commits, resolved
  through each `<arch>/<branch>/active` link (`flatpak_active()` in
  `05-startup-gates.sh`). The obvious `current` symlink resolves to a
  branch name, not a commit, so a redeployment under the same branch would
  previously not have re-run the gated work.
- A FAILED gated command no longer writes its stamp: the Sober overlay
  run keeps its original non-fatal behavior but retries on the next start
  instead of being silently recorded as done.
- `desktop-idle` measures real desktop input idle via `xprintidle` (now
  installed by `install-apps.sh`; verified working against TigerVNC), and
  uses the documented `CODESPACE_NAME` variable (falling back to
  `GITHUB_CODESPACE_NAME`).
- `20-browser.sh` writes the WebGL insurance prefs to both profile roots
  (`~/.mozilla/firefox` and the `~/.config/mozilla/firefox` layout the
  pkgforge Firefox AppImage actually uses).
- `CHANGES-perf.md` renamed to `CHANGES-codespace-cost-controls.md`: the
  sibling branch `perf/image-size-and-apps` (DONE, unmerged) also adds a
  `CHANGES-perf.md`, and the rename avoids that merge collision. Their
  branch otherwise touches only the image build path (install-apps.sh
  core/optional split, Dockerfile, devcontainer build args) and does not
  overlap this branch's module/setup/test changes; merging both later
  needs one trivial resolution (add `xprintidle` to their core apt list).

## What did NOT change

- The backup format: `desktop-backup`, `desktop-profile`, the data-dir
  `.gitignore`, and the `desktop-data` branch layout are untouched.
- The image build (`Dockerfile`, `install-apps.sh`) is untouched.
- The hook lifecycle (`first-start`/`normal-start`) is untouched.

## How it was tested

All testing was done inside a GitHub Codespace running on this branch
(`improved-spork-x597qvvpxpgj3v7j6`), created from the pushed branch:

- **Creation:** postCreate/postStart ran the new code; all startup stamps
  were written; desktop (fluxbox + noVNC on 6080) came up.
- **Resolution + WebGL:** `xrandr` on `:1` shows `1024x640`; the VNC server
  runs `-geometry 1024x640 -depth 24`; `xdpyinfo` lists 24-bit visuals;
  Firefox opened on `get.webgl.org` showed "Your browser supports WebGL"
  with the spinning cube (verified via desktop screenshot), and the
  `webgl.force-enabled` insurance prefs are now written to the profile
  root this Firefox build actually uses (`~/.config/mozilla/firefox`).
- **Repeat runs:** a manual `setup.sh normal-start` completes in ~200ms
  and prints `Sober library overlay already current - skipped.` /
  `/app hardlink tree already current - skipped.`
- **Stop → start:** stopped the codespace, restarted it (SSH available
  again in ~48s); stamp file mtimes were byte-identical to before the
  stop (no rewrite - the gated work did not re-run), and the desktop
  returned. (Whether postStartCommand itself executed on an SSH-triggered
  start could not be confirmed - the stamp evidence shows the expensive
  work did not repeat, which is the requirement.)
- **Rebuild:** `gh codespace rebuild` twice. The first rebuild hit a
  transient image-build failure (Codespaces fell back to a base image
  without any repo apps — no Dockerfile/install-apps.sh change on this
  branch, and all pinned download URLs verified live; a known-infra
  flake, not branch-related). The second rebuild built the full image
  (Firefox/Prism/Sober present), the rebuild's own lifecycle re-ran all
  gated work (fresh stamps), and the persisted `.first-start-complete`
  marker correctly kept first-start hooks from re-running.
- **Idempotence test:** `tests/idempotence-test.sh` passes inside the
  Codespace. It needed one fix for a pre-existing gap (not branch-
  specific): run unisolated in a Codespace, the real setup had already
  made `/home/steam/.steam` a symlink, so `link_dir` early-returned and
  the fixture's steam dir was never created; the test now saves/restores
  that symlink around the run.
- **Tools:** `desktop-stats` and `desktop-idle` produce correct output in
  the codespace; both menu entries appear exactly once in the Fluxbox
  menu; all pre-existing menu entries are intact.
- **Backup format:** `git diff origin/master..HEAD --
  .devcontainer/modules/10-persistence.sh
  .devcontainer/modules/40-profiles.sh` is empty; `desktop-backup` ran
  inside the codespace and committed locally (its push failed only
  because the SSH test session has no GitHub git credentials — the
  browser-opened codespace does).

## Known limitations

- The stamp directory lives outside `/workspaces`, so a manual `rm -rf`
  of it (or any change to the module/overlay/flatpak inputs) re-runs the
  gated work once — by design.
- `gh codespace ssh`-triggered starts do not run postStartCommand (a
  Codespaces CLI behavior; lifecycle commands run on editor/web starts),
  so stop→start timing evidence uses stamp mtimes plus a manual
  `normal-start` run.
- Startup timing measures the setup modules, not total codespace
  start time (which is dominated by the container start itself).
