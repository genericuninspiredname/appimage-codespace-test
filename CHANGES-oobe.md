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
  manual reopen; `classify_renderer` evidence rules.
- `tests/idempotence-test.sh` still passes (4 runs, state identical).
- Live Codespace test on this branch: first launch shows the screen,
  marker written, second start silent, manual reopen works, all five
  buttons exercised, repeat-start and rebuild behavior checked — see
  the final commit message and CHANGES updates below.

## Limitations
- "Windows host" is detected from WSL kernel markers; an ordinary Linux
  host without evidence reads "unknown". No Windows host was available
  for end-to-end testing (same as the windows-profile branch).
- Backup push state reflects the last known remote ref; the welcome
  never does a network fetch.
