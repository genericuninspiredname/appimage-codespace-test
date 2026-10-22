# CHANGES — Perf: image size and optional applications

Branch: `perf/image-size-and-apps` (from master `d67ee4c`)
Goal: reduce the container image size and avoid installing software most
users do not need, by separating core from optional applications.

## What changed

`install-apps.sh` (run at image-build time) now installs only the
**core** applications by default: the Firefox AppImage, the system
software-OpenGL/llvmpipe stack (libgl1-mesa-dri, libegl-mesa0,
libglx-mesa0 — the WebGL/diagnostics GL libraries), `htop` and `age`
(backup tools). Everything else became **optional**, opt-in via a new
`OPTIONAL_APPS` Docker build arg (space-separated tokens, default empty):

- `roblox` — Sober flatpak + GNOME runtime + library-overlay script
  (also `flatpak` and `python3`: the option explicitly requests python3
  for its overlay script; the desktop's own dependencies may install and
  use python independently — websockify on this image runs on python)
- `steam` — official `steam.deb` + i386 multilib GL stack
  (`dpkg --add-architecture i386` only happens with this token)
- `prism` — PrismLauncher AppImage + `openjdk-21-jre` fallback

Unknown tokens fail the build with a clear error. `apt-get clean` was
added next to the existing `rm -rf /var/lib/apt/lists/*` so downloaded
`.deb`s never enter the layer; the steam `.deb` and the per-AppImage
extraction temp dirs were already removed in the same layer that creates
them (kept). The optional install code is unchanged from master — only
gated.

The `OPTIONAL_APPS` arg is exposed in `.devcontainer/devcontainer.json`
(`"args": {"OPTIONAL_APPS": ""}`); opting in means editing that value
and rebuilding the container. The desktop UI is unchanged either way:
menu entries and launchers for the optional apps always exist and print
a "not installed" hint when the app files are absent. No changes to
`setup.sh`, the modules, the menu, or any startup code.

## Approximate size / build-time improvement

Measured in the test Codespace (`perf-image-size-test-jj4vwqq797vj3j765`,
2-core) with `du -sx /` — the observed **live root-filesystem usage** of
the running container, an approximate proxy for the avoided uncompressed
optional payload (it includes the identical desktop-lite/sshd feature
layers in both cases). Docker was not available inside this test
Codespace, so a direct baseline-vs-candidate `docker image inspect`
comparison was not possible; these are not registry download sizes:

| Build | rootfs | installed pkgs |
|-------|--------|----------------|
| core only (this branch, default) | 2,269,120 KB (~2.16 GiB) | 632 |
| core + all optional (`roblox steam prism`) | 5,847,212 KB (~5.57 GiB) | 912 |

**≈ 3.41 GiB (3,578,092 KiB, ~61.2%) less installed content by
default**; the optional payload is almost entirely the Sober/GNOME
flatpak runtime, the i386 Steam stack, Java and the PrismLauncher
AppImage. The core figure is consistent across a fresh creation
(2,269,120 KB) and two rebuilds (2,269,104 / 2,269,112 KB); the
all-optional figure is from the image-build path (a rebuild with the
arg set — see below). A supplementary live run of `install-apps.sh`
inside the core container gave 5,987,124 KB (slightly higher; the cause
was not investigated).

Build time (observed, same 2-core machine): the codespace was created
and the core-only image built and started in ~4–5 min (02:17–02:21
UTC; cache state of the base layers at creation is unknown). A rebuild
with unchanged code (cached core image) took ~21 s; the rebuild that
built the all-optional image took ~7.5 min (02:34–02:41 UTC). No
further build-time claim is inferred — only the size difference above
was measured.

## How it was tested (all inside the Codespace, on this branch)

- Codespace created from the branch: initial build (cache state of the
  base layers unknown) of the core-only image succeeded; desktop
  started (TigerVNC 24-bit 1280x800, fluxbox,
  websockify/noVNC on port 6080 → HTTP 200); first-start marker written.
- Core verified present and working: Firefox AppImage launched a real
  window on `:1` (verified as an X client), `htop`, `age` (encrypt/
  decrypt round-trip), llvmpipe GL libs (`libGL`, `swrast_dri.so`).
- WebGL functionally verified through the real UI launcher
  (`x-www-browser` on `:1`): a local test page created a WebGL 2.0
  context, rendered a red clear, and read back the exact pixels
  [255,0,0,255] — rendering works, not just library presence.
- Optional verified absent by default: no `flatpak`, no `/app`, no
  `sober-overlay.py`, no `/opt/apps/prismlauncher`, no steam binary.
- UI unchanged: menu entries (Roblox/Steam/Prism/Task Manager/Back Up
  Files) present exactly once; `steam`/`roblox`/`prismlauncher`
  launchers print the same "not installed" hints as before.
- Optional path via the real build-arg route: the codespace's working
  checkout had `OPTIONAL_APPS: "roblox steam prism"` set in
  `.devcontainer/devcontainer.json` (uncommitted), then
  `gh codespace rebuild` rebuilt the image through the Dockerfile ARG
  (~7.5 min). Result: all payloads deployed by the image build (Sober +
  GNOME runtime + overlay script, libc6 hold, steam.deb, PrismLauncher,
  openjdk-21, `/app/bin/sober` created by the postCreate setup, overlay
  applied — the live overlay's "no version information available"
  warnings are the documented master behavior), desktop up (fluxbox,
  24-bit, noVNC 200), core and menu intact, rootfs 5,847,212 KB.
  Restoring the arg to `""` and rebuilding again (~21 s, cached core
  image) returned the codespace to the exact core-only state above.
- Supplementary: `OPTIONAL_APPS="roblox steam prism" bash install-apps.sh`
  run live in the core container also deployed everything (its final
  success line printed; the pipeline's exit status was not captured —
  the rebuild test above is the authoritative evidence); a following
  `setup.sh normal-start` applied the overlay (1165 libs) with the
  desktop staying up.
- Validation: `OPTIONAL_APPS="bogus roblox"` fails with
  `ERROR: unknown OPTIONAL_APPS token 'bogus' (valid: roblox steam prism)`.
- Repeat runs: `setup.sh normal-start` twice + a no-arg manual run — all
  "Setup complete", state stable, desktop unaffected.
- Rebuild: `gh codespace rebuild` (~21 s, cached image) — desktop back
  up, core intact, optional payload gone (default is really core-only),
  first-start marker preserved (hooks correctly not re-run), menu
  intact, rootfs back to ~2.16 GiB.
- `tests/idempotence-test.sh`: **the suite FAILS** on this branch and
  **identically on master** at the "steam persistence dir missing"
  assertion — pre-existing, not caused by this branch. The four
  lifecycle runs and all snapshot-diff assertions before it pass; the
  suite aborts there, so its Phase 2 (hook-failure semantics) is never
  reached. Diagnosis (verified live): Codespaces blocks user
  namespaces, so the test's documented fallback runs unisolated and the
  fixture's `link_dir` for `/home/steam/.steam` returns early because
  the real setup already created that symlink
  (`→ /workspaces/desktop-data/private/steam-home/steam`).

## Files changed on this branch

- `install-apps.sh`: core/optional split, token validation, `apt-get
  clean`; optional sections unchanged, gated.
- `Dockerfile`: `ARG OPTIONAL_APPS=""` passed to `install-apps.sh`.
- `.devcontainer/devcontainer.json`: expose the `OPTIONAL_APPS` build arg.
- `README.md`: new "Core vs optional applications (image size)" section.
- `CHANGES-perf.md` (this file).

The runtime tests above were run against implementation commit `3bdc720`;
the commits after it are documentation-only.

## Limitations

- Size figures are live-rootfs measurements inside this test Codespace,
  not `docker image inspect` (docker was not available in this test
  Codespace); they include the identical devcontainer-feature layers in
  both variants and are an approximation of the image-content difference.
- The optional variant was verified by rebuilding the same Codespace
  with the arg set in its working checkout (no separate codespace or
  branch was created for it).
- Steam/Sober gameplay remains blocked inside Codespaces by their own
  anti-container checks (documented in README; unchanged by this branch).
