# CHANGES — First-run onboarding screen (OOBE)

Branch: `ui/oobe-and-desktop-diagnostics`
Goal: a lightweight first-run onboarding screen.

## What was added

### `.devcontainer/modules/75-oobe.sh`
New module (the layout's extension point: no shared file edited) that
installs one tool and one menu entry:

- **`desktop-welcome`** (`/usr/local/bin`, plain bash, reinstalled on every
  setup run like `desktop-backup`): a one-shot dialog — no framework, no
  background service. Shows:
  - **Environment:** Linux (GitHub Codespace) / Windows host (WSL) /
    unknown — detected from `CODESPACES`/`CODESPACE_NAME` and
    WSL kernel markers; never guessed.
  - **CPU** (cores, model, load average, container cgroup limit — host
    view labeled as such), **memory** (host usage + container cgroup
    limit), **screen resolution** (xdpyinfo; "unknown" without a display).
  - **WebGL status:** honestly "not tested" until a browser test runs.
    Uses the diagnostics branch's `desktop-doctor` when installed (the
    WebGL Test button runs it in a terminal so the report stays
    readable); without it the button falls back to a clearly-labeled
    GLX renderer check. GLX evidence is never presented as a WebGL test.
  - **Backup status:** last backup date/commit count from the
    desktop-data repo, uncommitted changes in `~/Files`, and push state
    against the last known remote ref (a local commit is never claimed
    as uploaded; git errors read "unknown", never "never backed up";
    only `files/` + `.gitignore` are checked, so markers never read as
    unbacked-up documents).
  - Buttons: **Browser** (`x-www-browser`), **Files** (nautilus
    `~/Files`), **WebGL Test**, **Performance Settings** (tips + the
    desktop's real `set-resolution` selector), **Stop Instructions**
    (read-only stop/delete instructions). Dialog rendering: zenity,
    falling back to xmessage; the dialog loops so every button can be
    used, and the body is rebuilt before each redisplay.
- **Fluxbox menu entry** `Welcome Screen` in its own managed block
  (`# >>> desktop-oobe >>>`), same pattern as the diagnostics branch —
  `50-menu.sh` untouched. The module restarts fluxbox itself when one
  is running (module 70 restarts before 75 edits the menu), so the
  entry is live immediately.

### `.devcontainer/hooks/normal-start.d/10-oobe.sh`
Normal-start hook that launches `desktop-welcome --auto` detached (it
never blocks setup). `--auto` is a no-op when the persistent marker
`$DATA_DIR/.oobe-shown` exists, waits (bounded, default 60 s) for the
X display, shows the screen once, and exits — nothing keeps running.

### First-launch semantics
- The marker is written **only after the dialog was really displayed**;
  a failed launch (no display, dialog error) writes nothing and is
  retried on the next start.
- The marker lives in the persistent data dir (survives rebuilds → no
  re-show after rebuild) but outside `files/`, so `desktop-backup`
  never commits it (a new codespace restored from a backup shows the
  screen again).
- Single-instance lock is a lock **directory** in `/tmp` with
  dead-holder + age staleness checks — deliberately not flock: a
  file-descriptor lock would be inherited by children (e.g. the browser
  launched from the Browser button) and stay "held" after exit.
- Manual reopen: menu entry or `desktop-welcome` (always shows).

## What did NOT change
- No shared module, `setup.sh`, `Dockerfile`, or `install-apps.sh`
  edits — the module hooks into the documented extension points only.
- No new apt packages, framework, or daemon. zenity is already provided
  by the desktop-lite feature (xmessage as fallback).

## Testing
- `tests/oobe-test.sh` (new, hermetic — same fixture pattern as
  `tests/idempotence-test.sh`): coordinator install + menu block
  idempotence; environment detection (Codespace / WSL / unknown);
  honest WebGL wording; resolution + GLX classification via stubs;
  backup_status variants (no repo / empty repo / backed up / dirty /
  unpushed / markers not documents); `--auto` gating, dialog-failure
  retry (marker absent), no-display failure, stale-lock stealing,
  manual reopen; extra-button dispatch for all six buttons in BOTH
  zenity styles — zenity 4 (label on stdout, exit 1) and zenity 3
  (label on stderr, exit 5) — plus zenity-3 timeout (exit 5, no
  label) NOT treated as Close; `classify_renderer` evidence rules.
  The zenity-4 case is a regression test: the first implementation
  read the label from stderr only, so on the image's zenity 4.0.1
  every extra button silently closed the dialog (caught live in the
  Codespace, then reproduced hermetically).
- `tests/idempotence-test.sh` still passes (4 runs, state identical).
- Live Codespace test (branch checkout at the final commit, desktop
  via noVNC, buttons clicked with xdotool, verified via screenshots
  and the script's own xtrace):
  - first launch (`setup.sh normal-start` with no marker): dialog
    auto-appears, shows Codespace environment, CPU, memory,
    resolution, honest WebGL line and backup status.
  - every button clicked and verified: Browser -> Firefox launched;
    Files -> nautilus opened ~/Files; WebGL Test -> terminal with the
    honest GLX fallback text (and, with desktop-doctor from the
    diagnostics branch installed as a test, the terminal runs
    desktop-doctor instead — the "diagnostics interface when
    available" path); Performance Settings -> tips window, whose
    "Open Resolution Settings" opens the real set-resolution
    selector; Stop Instructions -> the stop/billing instructions
    window; Close -> marker written, welcome exits.
  - marker gating: second start and repeated `normal-start` runs
    with the marker present show nothing (hook logs "welcome
    already shown - skipping").
  - manual reopen: Fluxbox menu -> Welcome Screen relaunches the
    dialog (clicked live); `desktop-welcome --print` works.
  - rebuild: the marker lives in /workspaces (persistent volume),
    so a rebuild keeps onboarding done; it is NOT in files/, so it
    is never committed by desktop-backup — a NEW codespace restored
    from a backup shows the welcome again (by design).
- Two real bugs were found and fixed during live testing: zenity 4
  prints extra-button labels to stdout with exit 1 (zenity 3 printed
  them to stderr with exit 5), and the label+warnings string does not
  end with the label (GTK/GVFS warnings follow it on stderr). Both
  are covered by the hermetic regression tests now.

## Re-verification at the final commit (second pass)

The branch was re-audited and re-tested inside a live Codespace at the
final commit; that pass found and fixed one real test bug:

- **`tests/oobe-test.sh` was not hermetic on a host with a live desktop.**
  Inside the Codespace (where the desktop is running on `:1`) the test
  failed: the phase-1 fixture welcome found the real X display and
  popped a real dialog on the host desktop (also holding the shared
  `/tmp/desktop-welcome.lock`), and the phase-2 "no display"
  assertions failed because `:1` was reachable. Root cause: Codespaces
  forbids `unshare` (user namespaces), so the test's mount isolation
  cannot run there, and `/tmp/.X11-unix` is shared with the host.
  Fix: a failing `xdpyinfo` stub in the fixture `PATH` (no setup module
  or hook other than 75-oobe.sh uses `xdpyinfo`) makes `find_display`
  fail on every host; the fixture welcome also gets its own lock and
  log via `DESKTOP_WELCOME_LOCK`/`DESKTOP_WELCOME_LOG`, and the hook
  now honors `DESKTOP_WELCOME_LOG` (default unchanged:
  `/tmp/desktop-welcome.log`) so test runs no longer clobber the host
  welcome log. The fixed test passes in the sandbox AND twice inside the
  live Codespace, leaving no stray dialogs, locks or markers.
- Live GUI re-check inside the Codespace: first launch with a fresh
  data dir auto-shows the dialog (screenshot-verified: environment,
  CPU, memory, resolution, WebGL and backup lines all render cleanly);
  Browser -> Firefox, Files -> nautilus on `~/Files`, WebGL Test ->
  xterm with the honest GLX fallback (tilix is not usable as root,
  xterm fallback as documented), Close -> dialog exits, marker written,
  `/tmp` lock cleaned; `--auto` with the marker present skips
  (`welcome already shown - skipping`); manual reopen always shows;
  `--print` works; `setup.sh normal-start` repeat-run is clean.
- Known, out-of-scope environment issue: `tests/idempotence-test.sh`
  fails inside the live Codespace on this branch and on `master`
  identically (steam fixture assertion; without `unshare` the steam
  module operates on the real `/home` paths). Pre-existing and
  unrelated to the OOBE; not fixed here to keep this branch scoped.

## Third pass: review fixes + rebuild verification

A second review of the second pass found and fixed three more issues:

- **Container memory was mis-scaled 1024x when a cgroup limit exists.**
  `build_body` fed cgroup BYTES (`memory.current`/`memory.max`) into
  `gib()`, which expects `/proc/meminfo` KiB. Codespaces sets no memory
  limit, so the live screen never hit the bug. New pure helper
  `fmt_cgroup_mem` converts bytes (1 GiB/4 GiB -> `1.0/4.0 GiB`), exposed
  as a `--cgroup-mem` test hook with hermetic regression tests.
- **The WebGL line claimed "not tested yet"** - one-time state the
  welcome cannot know: `desktop-doctor` (inspected on
  `diagnostics/webgl-and-rendering`) keeps no result state (run-and-
  report), and the welcome keeps none either. Wording now states that no
  test result is kept here; README updated to match. The
  `desktop-doctor` integration itself was re-verified against the real
  diagnostics branch: `command -v desktop-doctor` + running it with no
  arguments matches its documented contract.
- **`tests/oobe-test.sh` leaked a real Firefox into the teardown.** The
  `--auto`/manual gating subtests dispatch the Browser action before
  the extra-buttons section installed its stubs, so the real
  `x-www-browser` ran with the fixture `HOME`, kept writing its profile
  into `$WORK` after the test exited, and raced the EXIT trap's `rm -rf`
  ("Directory not empty" -> leftover `/tmp/oobe-test.*` dirs and orphan
  Firefox processes on the host). The `x-www-browser` stub now exists
  from phase-2 start. Verified in the live Codespace: zero leftover
  dirs, zero fixture-home Firefox processes, zero stray dialogs.

Rebuild verification (live Codespace, `gh codespace rebuild` twice):
- The `.oobe-shown` marker (persistent volume) survived both real
  rebuilds - directly observed after each one.
- Lifecycle behavior after the rebuild was verified by invoking the
  exact lifecycle commands manually (the same commands the lifecycle
  would run): postCreate-equivalent `setup.sh first-start` -> "First
  start already complete - skipping first-start hooks" (the persisted
  `.first-start-complete` marker keeps a rebuild in normal-start
  territory), then `setup.sh normal-start` -> welcome hook runs, marker
  present, no dialog auto-shown. The automatic post-rebuild hook run
  is evidenced only indirectly: no dialog appeared and the hook's log
  file was created (but captured no skip line), so the automatic path
  is not directly proven - the skip itself is, by direct invocation:
  `desktop-welcome --auto` prints "welcome already shown - skipping"
  and exits 0.
- Final hook check on the live desktop (after the image anomaly below,
  with screenshot tools reinstalled in the container): the real
  `10-oobe.sh` was invoked with isolated data/lock/log paths. First
  run: the dialog rendered with the final wording (screenshot-verified:
  WebGL line complete and unclipped, all six buttons fully labeled);
  Close wrote the marker and cleaned the lock. Second run: the hook
  logged "welcome already shown - skipping" and showed nothing.
- Manual reopen after the rebuild shows the dialog (verified live with
  the new WebGL wording rendering correctly).
- Observed anomaly, cause not established (not diagnosed as a platform
  defect): the first rebuild produced a container without the
  desktop-lite feature binaries (no fluxbox) and an ssh-start that ran
  no lifecycle commands; the second rebuild produced a working desktop
  (fluxbox up, setup ran) but the container lacked `xdotool`/`import`
  until reinstalled, so the post-rebuild dialog was verified via the
  zenity process command line first and by screenshot after the tools
  were reinstalled. Nothing on this branch affects the image build.

## Limitations
- "Windows host" is detected from WSL kernel markers; an ordinary Linux
  host without evidence reads "unknown". No Windows host was available
  for end-to-end testing (same as the windows-profile branch).
- Backup push state reflects the last known remote ref; the welcome
  never does a network fetch.
- Cosmetic, seen live: the xterm fallback for WebGL/Files/Resolution
  wraps long lines at ~80 columns; the Stop Instructions window's
  last text line is partially clipped until scrolled. Pre-existing
  environment issues affect it too: tilix exits immediately when
  running as root (the script falls back to xterm), and bash prints
  a libtinfo version warning at startup.
- The zenity fallback path (xmessage) could not be exercised live —
  zenity is always present in this image; it is covered by the
  hermetic test's stubs only.
