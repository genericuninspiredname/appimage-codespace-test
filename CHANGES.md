# CHANGES — Steam + PrismLauncher integrated onto the foundation layout

Branch: `foundation/merge-safe-layout` (on top of the modular-layout commit
`2610195`, from master `0972a18b`).
Goal: test the current foundation branch and merge the useful details of the
other branches into it, so they can flow into `main` from this branch.

## What was merged, and what was not

- `steam-prismlauncher` — **merged** (both commits):
  - `5c954c3` (wip: install logic, dedicated steam user, launchers,
    persistence, menu entries): ported into the modular layout —
    new module `.devcontainer/modules/35-steam.sh` (sections 2c/2d, code
    unchanged), menu entries added to the managed block in
    `.devcontainer/modules/50-menu.sh`, and the `install-apps.sh` changes
    (i386 multilib stack, official steam.deb, PrismLauncher AppImage via
    `install_appimage_sqfs()`, openjdk-21 fallback) applied as-is.
  - `c0eeca5` (`DONE`): README Steam + Minecraft sections and the proof
    screenshot ported; this CHANGES.md replaces that branch's changelog
    (which documented the same work against the pre-modular layout).
- `codespace-animated-robot-jjqj9wg7gvwvhq6x5` — **nothing to merge**:
  `git diff` against master is empty (its content is already in master via
  merge commit `0972a18`). One stray edit from that export was found and
  removed: it had deleted two lines of a comment inside the `link_dir`
  function in `10-persistence.sh`, leaving the sentence mangled; the
  original comment is restored.
- The DONE commits on both other branches were inspected and do not
  conflict with this work (the steam DONE commit is docs+image only).

## Files changed on this branch (integration commit)

- `.devcontainer/modules/35-steam.sh` (new): Steam + PrismLauncher module.
- `.devcontainer/modules/50-menu.sh`: `Steam` and `Prism Launcher` menu
  entries in the managed block.
- `.devcontainer/modules/10-persistence.sh`: restored the comment lines
  accidentally deleted by the codespace export.
- `install-apps.sh`: i386 multilib, Steam .deb, PrismLauncher AppImage,
  openjdk-21 fallback.
- `tests/idempotence-test.sh`: `id` stub now also answers for the `steam`
  user; new assertions for the steam/prism launchers, persistence dirs and
  menu entries (exactly once).
- `README.md`: Steam + Minecraft (PrismLauncher) sections.
- `assets/steam-prism-sandbox-proof.png`: proof screenshot from the steam
  branch (both clients rendering in a container sandbox).
- `CHANGES.md` (this file).

## How it was tested

- `bash -n` on every changed script; `tests/idempotence-test.sh` passes
  (4 lifecycle runs with byte-identical state + hook-failure phase) with
  the new module loaded — the steam/prism state is part of the snapshot.
  The test ran on a host with user namespaces available, i.e. inside a
  private user+mount namespace — nothing outside the temp dir was touched.
- Full Codespace verification on this branch (machine `basicLinux32gb`)
  is in progress: image build with the new `install-apps.sh` (i386 stack,
  steam.deb, PrismLauncher AppImage), postCreate/postStart lifecycle, menu
  entries, launcher wrappers, persistence symlinks, and a full container
  rebuild (postCreate re-fires; the completion marker gates the first-start
  hooks) plus a repeat run of the setup coordinator. Outcomes are recorded
  in the final commit's report.

## Known limitations

- Steam/Prism are exercised to the client UI (sign-in window / launcher
  window), not to actual gameplay — that needs user accounts.
- The PrismLauncher version is resolved to the latest release at image
  build time (pinned fallback `11.1.1`); upgrades are deliberate rebuilds.
