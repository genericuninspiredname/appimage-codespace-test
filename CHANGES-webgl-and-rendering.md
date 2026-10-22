# Changes: diagnostics/webgl-and-rendering

`desktop-doctor` — a lightweight, terminal-first diagnostics tool for the
codespace desktop. Installed by the new module
`.devcontainer/modules/72-webgl-diagnostics.sh` (its own files only; no
existing module is edited). Also adds a Fluxbox menu entry
(Diagnostics) through its own managed menu block, so `50-menu.sh` is
untouched.

## What it reports

| Area | What you get |
|------|--------------|
| WebGL | Real context-creation probe in the app's browser (Firefox, headless, its normal security settings — nothing is disabled to make the probe pass), plus the managed `webgl.*` prefs from every Firefox profile |
| Rendering | The unmasked renderer string, classified as **software** (llvmpipe/softpipe/swrast/SwiftShader/…), **hardware**, or **unknown** when the string is masked or the probe is inconclusive; GLX (`glxinfo -B`) evidence on the desktop display as corroboration |
| Display | Current desktop resolution and color depth via `xdpyinfo` on the live X display (a virtual Xvnc/TigerVNC display is labeled as such); works from SSH too by probing `:1`/`:0` |
| CPU | Usage sampled over 1 s from `/proc/stat` (host view, labeled), visible core count, load average, and the container's cgroup CPU quota — scopes are labeled, host counters are never presented as container limits |
| Memory | Container usage vs cgroup limit (with percent and swap), plus host totals from `/proc/meminfo`, clearly labeled |

Every failing or degraded check produces a numbered troubleshooting hint
at the end (restart the browser, where the desktop lives, how to lower
the resolution, what software rendering means in a codespace, …).

## Usage

```bash
desktop-doctor              # full report (WebGL probe included)
desktop-doctor --no-probe   # prefs + GLX evidence only, no browser launch
desktop-doctor --help       # usage and exit codes
```

Exit codes: `0` = all checks ran and none failed (warnings allowed);
`1` = at least one check failed or could not run.

Menu: right-click desktop → **Diagnostics** (opens the tool in a
terminal), next to the existing Task Manager entry.

## Design notes

- The WebGL probe launches the real Firefox (`/opt/apps/firefox/AppRun`,
  overridable via `DESKTOP_FIREFOX`) headless with a throwaway profile.
  A small local page tries `webgl2` → `webgl` → `experimental-webgl`,
  reads `WEBGL_debug_renderer_info`, and reports back to a one-shot
  local collector; the browser is killed and the temp profile deleted
  afterwards. No security flags are set or cleared — the probe either
  works with the browser's normal configuration or reports honestly.
- "Could not run the probe" is reported as **unknown**, never as a
  passing WebGL check. A missing renderer string is **unknown**, never
  silently "hardware".
- CPU percentage is a sampled counter interval, not the load average
  (both are reported, labeled). Memory distinguishes host totals from
  the container's cgroup limit.

## Files changed

- `.devcontainer/modules/72-webgl-diagnostics.sh` (new) — installs the
  tool into `$BIN_DIR` (idempotent: rewritten on every setup run) and
  the menu entry (managed block, replaced wholesale, never duplicated).
- `README.md` — module table row + short Diagnostics section.
- `tests/diagnostics-test.sh` (new) — unit tests for the pure helpers
  (renderer classification, cgroup parsing, display parsing) that do
  not need the built image; the full tool is exercised in the codespace
  itself.

## Test results (branch `diagnostics/webgl-and-rendering`)

Verified locally (bash syntax check, `tests/diagnostics-test.sh`, and the
existing `tests/idempotence-test.sh` — all pass), and in a real
Codespace built from this branch:

- `desktop-doctor` full run: display section verified (1280x800,
  24-bit, virtual VNC display), CPU and memory sections verified with
  labeled host/container scopes; exit code and repeat runs behave as
  documented (`--no-probe`, unknown option rejection, second run).
- Setup re-run on a live codespace (`normal-start` after pulling a
  fix) applies the tool cleanly without disturbing the running desktop.
- WebGL probe: **the success path could not be verified in the test
codespace, and this is a pre-existing environment issue, not a gap in
the tool**: the Firefox AppImage in this environment opens a window but
never renders any page (local `file://` and remote URLs alike), on
master as well as on this branch (verified on a separate master
codespace), with the project launcher and with fluxbox-remote, and with
every sandbox env variation tried. The probe therefore times out, and
the tool reports exactly that: "browser launched but never loaded the
probe page", with a hint that a browser unable to open any page is a
browser-build problem, not a WebGL-specific one. No security flags
were added or cleared to make the probe pass — the browser runs with
its normal configuration.

Remaining limitations:

- The WebGL probe's positive path ("available", renderer reported) is
  implemented but unverified in this environment for the reason above.
- `glxinfo` is not part of the image (not in `install-apps.sh` on
  master), so GLX evidence appears only when it is installed manually.
- CPU/memory read the host `/proc` (Codespaces containers see the host
  view); the tool labels the scopes rather than guessing.
