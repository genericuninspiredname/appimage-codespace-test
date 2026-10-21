# Lifecycle hooks

Stable extension points so feature branches can add startup behavior
without touching shared files (that is the point of the
`foundation/merge-safe-layout` refactor).

## Directories

- `first-start.d/` - scripts run once per codespace **lifetime**: during
  creation (`postCreateCommand`). Note that `postCreateCommand` also
  fires on a container rebuild; the coordinator gates on the persisted
  marker (`$DATA_DIR/.first-start-complete`) so the hooks still run only
  once per codespace. The marker is only written after every first-start
  hook succeeded - a failed hook is retried on the next run.
- `normal-start.d/` - scripts run on every start, including starts after
  a rebuild (`postStartCommand`).

## Contract

- Name scripts `NN-description.sh` (two-digit prefix); they run in
  lexical order within their directory.
- Scripts run with `bash` AFTER all setup modules, so they see the fully
  configured environment.
- The coordinator exports `HOMEDIR`, `DATA_DIR`, `BIN_DIR`, `REPO_DIR`,
  `REMOTE_URL`, and `DESKTOP_*` overrides are honored; `HOME` is the
  user's real home.
- A failing hook prints a warning and does not abort the rest of setup,
  nor does it stop later hooks from running - but it IS reported in the
  final status line, and on a first start it prevents the completion
  marker, so the hook is retried on the next run. Keep hooks cheap and
  idempotent: normal-start hooks run on every start.
- Do not edit files owned by a module; add your own files instead. This
  is what keeps future branches conflict-free.

## First-start detection

`setup.sh` records completion of the first start in
`$DATA_DIR/.first-start-complete` (inside the persistent data dir, so it
survives rebuilds). `first-start` hooks therefore do not re-run after a
rebuild - if your feature needs per-boot behavior, use `normal-start.d`.
