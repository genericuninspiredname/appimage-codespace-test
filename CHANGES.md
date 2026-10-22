# CHANGES — Steam + PrismLauncher integrated onto the foundation layout

Branch: `foundation/merge-safe-layout` (on top of the modular-layout commit
`2610195`, from master `0972a18b`).
Goal: test the current foundation branch and merge the useful details of the
other branches into it, so they can flow into `main` from this branch.

## What was merged, and what was not

- `steam-prismlauncher` — **selectively ported** (both commits inspected;
  nothing merged as-is — the code was ported onto the modular layout, see
  below):
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
- The `DONE` commit on `steam-prismlauncher` (`c0eeca5`) was inspected and
  does not conflict with this work (it is docs+screenshot only; those
  details are ported and attributed above). The export branch has no
  `DONE` commit.

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
- Full Codespace verification on this branch (machine `basicLinux32gb`,
  codespace `foundation-merge-safe-test2-…`, commit `d36e83e`):
  - **Baseline test of the previous branch tip (`2610195`)**: codespace
    created on the branch; postCreate (first-start) ran, first-start marker
    written, desktop up (Xvnc :1 + fluxbox + noVNC on 6080), launchers and
    menu as expected; a repeated `normal-start` run left the fluxbox menu
    byte-identical with the managed block exactly once (state checks; the
    integrated-commit repeat below additionally captured the direct exit
    code). The local fixture test also ran on this host with user
    namespaces available (`unshare -rm` works; the test's ISOLATED=1 path
    was used - nothing outside its temp dir is touched).
  - **Image rebuild with the new `install-apps.sh`**: full rebuild re-ran
    the installer — `dpkg --print-foreign-architectures` reports `i386`,
    `/usr/bin/steam` (steam-launcher package) installed, `/opt/apps/`
    contains `firefox` + `prismlauncher`, Java 21 present.
  - **Lifecycle on rebuild**: postCreate re-fired but the first-start
    marker (persisted in `/workspaces`) correctly gated the first-start
    hooks; the new `35-steam.sh` module ran and installed the
    `steam`/`prismlauncher` wrappers and persistence symlinks.
  - **Live desktop verification** (screenshots taken via scrot on the
    running X server): the Fluxbox menu contains the `Steam` and
    `Prism Launcher` entries exactly once; **PrismLauncher 11.1.1**
    launches via the wrapper — Quick Setup wizard renders, and after
    finishing it the main window (instance list, toolbar, accounts menu)
    renders fully. Note: the wizard re-appears on each launch while no
    Microsoft account is configured (PrismLauncher's own first-run UX —
    the account step is never "done" without an account); this is not a
    persistence failure — the data dirs, themes, translations and
    instance folders written by earlier runs all survive restarts.
  - **Steam — blocked in Codespaces (new finding, a failed runtime test)**:
    the client bootstrap starts as the dedicated `steam` user but stops
    at Steam's own error dialog: "Steam now requires user namespaces to
    be enabled". Codespaces blocks unprivileged user namespaces (the
    same kernel restriction documented for Flatpak/Sober in the README);
    no workaround was found or verified. (The interactive dependency
    prompt during the first bootstrap was manually dismissed during
    testing.) The steam branch's README claim that Steam "works in the
    container" was based on a sandbox where namespaces were allowed and
    does not hold in Codespaces; the README section was rewritten
    accordingly. The install, user, persistence and wrapper plumbing are
    retained as a documented blocked component — verified working except
    the client itself.
  - **Repeat run of the integrated coordinator (`d36e83e`)**, direct
    exit-code capture: `bash .devcontainer/setup.sh normal-start` →
    exit 0, menu byte-identical, all persistence symlinks unchanged,
    sentinel contents intact, managed blocks each exactly once. The only
    state change: the steam module re-asserted `steam:steam` ownership
    of the steam-home dir (its intended behavior).
  - **Full rebuild persistence**: sentinel files seeded in BOTH new app
    data destinations (steam-home and prism) before the rebuild survived
    it with contents, symlink targets and usable ownership intact;
    first-start marker persisted from before the rebuild (its presence
    was observed; hook skipping semantics are covered by the fixture
    test's phase 1/2 assertions).
  - **Stop/start cycle**: sentinel file in the persistent Prism data dir
    survived; postStart (normal-start) re-ran, desktop came back up,
    menu/launchers intact and not duplicated.

## Known limitations

- **Steam cannot run inside GitHub Codespaces** (its bootstrap requires
  user namespaces, which Codespaces blocks) — see the README Steam
  section. Everything except the client itself is verified there.
- PrismLauncher is verified to the launcher UI (wizard + main window);
  actually launching a Minecraft instance needs a Microsoft account.
- The PrismLauncher version is resolved to the latest release at image
  build time (pinned fallback `11.1.1`); upgrades are deliberate rebuilds.
