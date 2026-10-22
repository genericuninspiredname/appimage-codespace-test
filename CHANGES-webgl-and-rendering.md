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

## Test results (codespace, branch `diagnostics/webgl-and-rendering`)

- `bash -n` on the module and the installed tool: clean.
- `tests/idempotence-test.sh` (existing suite, extended fixture): pass —
  setup runs 4x with byte-identical state, managed blocks appear once.
- `tests/diagnostics-test.sh`: pass.
- In the codespace: `desktop-doctor` full run (WebGL available via
  software llvmpipe, resolution 1280x800 depth 24, CPU/memory sampled),
  repeat run, `--no-probe` run, and re-run after a container rebuild —
  all behave as documented. Details in the branch's final report.
