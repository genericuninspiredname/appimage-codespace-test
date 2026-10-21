# CHANGES — Foundation: merge-safe layout

Branch: `foundation/merge-safe-layout` (from master `0972a18b`)
Goal: refactor the repository so future feature branches can merge with
minimal conflicts. This branch is the foundation the other feature
branches build on.

## What changed

### `.devcontainer/setup.sh` → coordinator + modules

The 678-line monolith is now a short **coordinator** plus seven focused
modules in `.devcontainer/modules/`, sourced in lexical order. The code
was moved **verbatim** — verified line-by-line against the original
(see "How it was tested"):

| Module | Content (original setup.sh sections) |
|--------|---------------------------------------|
| `10-persistence.sh` | §1 persistent data dir + restore, §2 `link_dir` + home symlinks, §3 `desktop-backup` |
| `20-browser.sh` | namespaces-check flag, `x-www-browser` launcher, WebGL user-pref tuning |
| `30-roblox.sh` | §1b Sober library overlay, §2a dedicated `roblox` user, `/app` + runtime-share provisioning, §2b launchers + tuned config (image-dependent steps guarded on Sober/flatpak being present; the user, persistence links and launchers are always installed, as before) |
| `40-profiles.sh` | §3b `desktop-profile` encrypted save-profile tool |
| `50-menu.sh` | §4 Fluxbox menu managed block |
| `60-fluxbox.sh` | §5 wallpaper, init, style overlay, keys, SHORTCUTS |
| `70-diagnostics.sh` | git `safe.directory` fix, reapply to a running desktop (fluxbox restart) |

The coordinator keeps the original environment resolution
(`DESKTOP_HOME`, `DESKTOP_DATA_DIR`, …), `set -e` semantics (a failing
module aborts the run exactly as a failing section did before), and the
final status message. The WebGL tuning moved from after the Fluxbox
section into the browser module — it has no dependency on the Fluxbox
step, and the resulting state is identical (verified by diffing the old
and new script outputs against identical fixtures).

**One intentional behavior fix:** the `git config --global --add
safe.directory` calls in the diagnostics module appended a duplicate
entry on every run (the only non-idempotent step left in the script).
They now add each entry only when absent. This is required by the
"safe to run repeatedly" goal; unrelated values are preserved.

### Lifecycle hooks

`.devcontainer/hooks/first-start.d/` and `.devcontainer/hooks/normal-start.d/`
are stable extension points (contract in `.devcontainer/hooks/README.md`):

- `postCreateCommand` → `setup.sh first-start`. Note `postCreateCommand`
  also fires on a container rebuild, so an explicit first-start is
  gated on the persisted marker (`$DATA_DIR/.first-start-complete`):
  first-start hooks run once per codespace **lifetime**.
- `postStartCommand` → `setup.sh normal-start`. Normal-start hooks run
  on every start, including after rebuilds.
- Hooks run in lexical order after all modules; a failing hook is
  reported loudly, does not stop later hooks, and does not abort the
  desktop setup.
- The completion marker is written only after every first-start hook
  succeeded — a failed hook is retried on the next run.
- A manual `bash .devcontainer/setup.sh` with no argument infers the
  mode from the persisted marker.
- Empty hook directories are fine (the shipped ones contain only a
  README).

### `.devcontainer/devcontainer.json`

`postCreateCommand` / `postStartCommand` now pass the lifecycle mode
(`first-start` / `normal-start`). No other changes.

### `tests/idempotence-test.sh` (new)

Runs the real coordinator against an isolated fixture and verifies
repeat-run safety and the hook lifecycle:

- **Phase 1** — four runs: `first-start`, `normal-start`, a repeated
  `first-start` (a rebuild re-fires postCreate) and a no-argument run.
  Asserts all runs exit 0; observable state (persistent data dir, home
  tree, installed tool scripts, fluxbox configs, symlinks) is
  byte-identical across all runs; managed blocks (`desktop-apps`,
  `desktop-init`, `desktop-overlay`, `desktop-keys`) appear exactly
  once; user-authored content is preserved (menu entries, keys, prefs);
  the home→data-dir migration and symlinks are correct; the wallpaper
  is copied; the `safe.directory` entries appear exactly once.
- **Phase 2** — hook-failure semantics: a failing first-start hook
  warns, later hooks still run, the completion marker is NOT written,
  and the hook is retried on the next run.

The fixture stubs commands that need the built image or a real root
system (`useradd`, `chown`, `xhost`, `id` for the roblox user) and
isolates git's global config via `GIT_CONFIG_GLOBAL`. When user
namespaces are available the run happens inside a private user+mount
namespace (tmpfs over `/run` and `/home`) so nothing outside the temp
dir is touched; when they are not (e.g. Codespaces, which blocks
`unshare`) and the test runs as root, it runs directly — the side
effects are the same paths the real setup manages and self-heal on the
next real setup run.

## How it was tested

- `bash -n` on the coordinator, every module, and the test.
- **Line-level completeness:** every non-blank line of the original
  `master` setup.sh was diffed against the assembled
  coordinator+modules. The only original lines not present verbatim are
  the old header comments, the final echo (moved into the coordinator)
  and the two unguarded `git config --add` lines (replaced by the
  guarded `add_safe_directory`, see above). No logic is missing — this
  caught and fixed a missing block during development (the `/app`
  directory provisioning in the Roblox module).
- **Behavioral equivalence:** the original `master` setup.sh and the new
  coordinator were run against two identical fixtures (seeded home with
  fluxbox configs, Firefox profile, user files, Sober dir) and the
  resulting state trees were diffed with path normalization. The only
  differences: the new `.first-start-complete` marker (by design) and
  the timestamped `Imported-from-home-*` directory names (inherent to
  the original behavior). Everything else is byte-identical.
- `tests/idempotence-test.sh` passes (4 runs + hook-failure phase).
- No-argument invocation (manual run) infers the mode correctly and is
  repeat-safe; invalid modes exit 2 with a usage message.

### Codespace test — blocked (billing)

Codespaces creation and start currently fail with **HTTP 402** (account
out of monthly free usage / budget) — the same blocker documented on the
`steam-prismlauncher` branch. The devcontainer lifecycle was therefore
verified in an isolated namespace sandbox that exercises the real
coordinator end-to-end (all modules, all guards, both lifecycle modes)
without touching the host. **The full Codespace run (image build +
postCreate + postStart against a live codespace) is still pending
codespace access.**

Next step for the reviewer/owner: once Codespaces credit is available,
create a codespace on this branch and confirm creation, a restart, and
a rebuild (the repeat-run/rebuild safety is what the idempotence test
covers; the only untested part is the Codespaces plumbing itself, which
is unchanged apart from the two mode arguments).

## Compatibility with other branches

- `steam-prismlauncher` (commit `DONE` = `c0eeca5`): the DONE commit
  itself touches only `CHANGES.md`, `README.md` and a screenshot — no
  conflict with this refactor. Its parent commit `5c954c3` adds Steam/
  Prism sections **inside the old monolithic setup.sh**; when that
  branch is rebased/merged onto this foundation, those additions should
  move into a new module (e.g. `35-steam.sh`) or hook scripts, and its
  menu entries need to be added to the managed block in `50-menu.sh`
  (which is replaced wholesale on each run). This file is named
  `CHANGES-foundation.md` (not `CHANGES.md`) to avoid an add/add
  collision with that branch's changelog.
- `codespace-animated-robot-jjqj9wg7gvwvhq6x5`: no `DONE` commit;
  changes are image-build side (`Dockerfile`/`install-apps.sh` area) and
  do not overlap with this branch.

## Files changed

- `.devcontainer/setup.sh` (rewritten as coordinator; logic moved out)
- `.devcontainer/modules/{10-persistence,20-browser,30-roblox,40-profiles,50-menu,60-fluxbox,70-diagnostics}.sh` (new)
- `.devcontainer/hooks/README.md`, `.devcontainer/hooks/first-start.d/README.md`, `.devcontainer/hooks/normal-start.d/README.md` (new)
- `.devcontainer/devcontainer.json` (lifecycle mode arguments)
- `tests/idempotence-test.sh` (new)
- `README.md` (repository-layout section)
- `CHANGES-foundation.md` (this file)
