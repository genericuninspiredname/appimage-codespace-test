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

## What did NOT change

- The backup format: `desktop-backup`, `desktop-profile`, the data-dir
  `.gitignore`, and the `desktop-data` branch layout are untouched.
- The image build (`Dockerfile`, `install-apps.sh`) is untouched.
- The hook lifecycle (`first-start`/`normal-start`) is untouched.

## How it was tested

See "How it was tested" in this file's final revision and the report in the
branch's DONE commit context:

- `tests/idempotence-test.sh` extended: fixture exports
  `DESKTOP_STAMP_DIR`; new assertions for `desktop-stats`/`desktop-idle`
  installation, the two new menu entries (exactly once), gate-helper
  semantics (missing stamp runs, unchanged input skips, changed input
  re-runs), the timing line, and state identity across the extra run.
- Full test run inside a GitHub Codespace on this branch (first-start and
  normal-start, plus repeat-run timing comparison showing the gated
  sections skip on the second run).
