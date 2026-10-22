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
| WebGL | Context-creation probe in the app's browser: the probe page is served by a local one-shot server, loaded by the browser on the desktop display when one is reachable (the same rendering path as a normal session; headless otherwise), and reports back which context type it could create. The probe distinguishes "page never loaded" from "page loaded, no result" from "browser exited immediately". Firefox's managed `webgl.*` prefs are listed too. |
| Rendering | The renderer string, classified as **software** (llvmpipe/softpipe/swrast/SwiftShader/…), **hardware**, or **unknown** — masked or generic renderer strings (no `WEBGL_debug_renderer_info`) stay **unknown**, never "hardware". GLX (`glxinfo -B`) evidence on the desktop display as corroboration when the browser probe is inconclusive. |
| Display | Current desktop resolution and color depth via `xdpyinfo` on the live X display; a TigerVNC/Xvnc virtual display is labeled as such. Works from SSH too by probing `:1`/`:0`. |
| CPU | Usage sampled over 1 s from `/proc/stat` (host view, labeled), visible core count, load average, and the container's cgroup CPU quota — scopes are labeled, host counters are never presented as container limits. |
| Memory | Container usage vs cgroup limit (with percent and swap), plus host totals from `/proc/meminfo`, clearly labeled. |

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
`1` = at least one check failed or could not run (including a default
WebGL probe that produced no result — `--no-probe` is the explicit,
allowed skip); `2` = bad command-line option.

Menu: right-click desktop → **Diagnostics** (opens the tool in a
terminal), next to the existing Task Manager entry.

## Design notes

- The probe serves its page from a local one-shot server (ephemeral
  port, same-origin result endpoint) and launches the app's browser
  against it — on the desktop display when one is reachable, headless
  otherwise; the report states which mode ran. A browser window may
  flash briefly on the desktop during a display-mode probe.
- Failure modes are distinguished: browser missing (rc 1) vs launched
  but no result (rc 2), page never fetched vs fetched without result,
  and immediate browser exit (with the first stderr lines shown).
- No security flags are set or cleared by the tool — the browser runs
  with its normal configuration, and the probe reports honestly when it
  cannot obtain a result. (During environment diagnosis outside the
  tool, the project launcher's existing env vars were tried; nothing
  of that kind ships here.)
- "Could not run the probe" is reported as a failed check (nonzero
  exit), never as a passing WebGL result. A masked renderer string is
  **unknown**, never silently "hardware".
- CPU percentage is a sampled counter interval, not the load average
  (both are reported, labeled). Memory distinguishes host totals from
  the container's cgroup limit.

## Files changed

- `.devcontainer/modules/72-webgl-diagnostics.sh` (new) — installs the
  tool into `$BIN_DIR` (idempotent: rewritten on every setup run) and
  the menu entry (managed block, replaced wholesale, never duplicated).
- `tests/diagnostics-test.sh` (new) — unit tests for the pure helpers
  (renderer classification incl. masked strings, cgroup parsing, xdpyinfo
  parsing) plus end-to-end tests of `probe_webgl` with a stub browser
  (success, context-unavailable, timeout, immediate exit, temp-file
  cleanup, missing browser) and module idempotence. These run without
  the built image; the full tool is exercised in the codespace itself.
- `README.md` — module table row + short Diagnostics section (small
  additive edits; other branches also touch README, so textual merge
  conflicts are possible there and left to the maintainer).
- `CHANGES-webgl-and-rendering.md` — this file.

## Test results (branch `diagnostics/webgl-and-rendering`)

- `tests/diagnostics-test.sh`: all pass, locally and inside the
  codespace — pure helpers, stub-browser end-to-end probe paths, and
  module idempotence (install + menu block appear exactly once).
- `tests/idempotence-test.sh` (existing suite): passes locally (4
  runs, byte-identical state). In the codespace it fails at the
  pre-existing "steam persistence dir missing" check — that failure
  reproduces identically on master's own checkout in the same
  environment, so it is not caused by this branch.
- Codespace built from this branch: `desktop-doctor` verified — display
  section (1280x800, 24-bit, virtual VNC label), CPU and memory
  sections with labeled host/container scopes, repeat runs,
  `--no-probe`, unknown-option rejection, menu entry, `--help`.
- Startup / re-run / rebuild: postStart re-runs setup cleanly over a
  live desktop; a real `gh codespace rebuild` re-created the container
  and reinstalled the tool via setup (a first rebuild attempt produced
  a degraded container with the plain base image — observed once,
  cause not established; the second rebuild built the project image
  correctly).
- WebGL probe in the codespace: verified end-to-end — the browser
  loaded the served probe page on the desktop display and reported a
  `webgl2` context with its renderer string; the tool classified the
  masked "Generic Renderer" string as **unknown** (not hardware),
  honestly, since no real renderer implementation was named. On the
  codespace's first container instance (before a rebuild) the browser
  opened a window but never loaded any page (remote and `file://` URLs
  alike), so the probe there reported the failed check with a nonzero
  exit — cause of that instance's failure not established; after the
  rebuild the browser rendered normally. Both the success path and the
  honest-failure path were exercised against the real browser, and the
  full matrix (success, no-context, timeout, early exit, cleanup,
  missing browser) is covered by the stub-browser tests.

Remaining limitations:

- The renderer string the real browser reports in this environment is
  a masked "Generic Renderer", so the tool correctly classifies
  rendering as **unknown** rather than guessing software/hardware;
  the software-renderer classification is verified through GLX
  evidence and unit tests, not through the browser's own string.
- `glxinfo` is not part of the image (not in `install-apps.sh` on
  master), so GLX evidence appears only when it is installed manually;
  the tool notes this.
- CPU/memory read the host `/proc` (Codespaces containers see the host
  view); the tool labels the scopes rather than guessing.
