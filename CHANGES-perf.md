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
  (also `flatpak` and `python3`, which nothing else needs)
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
2-core) with `du -sx /` — uncompressed root-filesystem usage of the
running container, which includes the identical desktop-lite/sshd
feature layers in both cases (docker is not available inside a
Codespace, so this is the closest equivalent of image size):

| Build | rootfs | installed pkgs |
|-------|--------|----------------|
| core only (this branch, default) | 2,269,120 KB (~2.16 GiB) | 632 |
| core + all optional (`roblox steam prism`) | 5,987,124 KB (~5.71 GiB) | 912 |

**≈ 3.48 GiB (~62%) smaller** by default; the optional payload is almost
entirely the Sober/GNOME flatpak runtime, the i386 Steam stack, Java and
the PrismLauncher AppImage.

Build time (same 2-core machine class): the core-only image built during
Codespace creation in ~4–5 min (cold, no cache); installing the full
optional payload afterwards took a further ~4 min, so the default build
saves roughly that much build time too. A cached rebuild (unchanged
code) takes ~21 s. These are approximate, single-run figures.

## How it was tested (all inside the Codespace, on this branch)

- Codespace created from the branch: cold build of the core-only image
  succeeded; desktop started (TigerVNC 24-bit 1280x800, fluxbox,
  websockify/noVNC on port 6080 → HTTP 200); first-start marker written.
- Core verified present and working: Firefox AppImage launched a real
  window on `:1` (verified as an X client), `htop`, `age` (encrypt/
  decrypt round-trip), llvmpipe GL libs (`libGL`, `swrast_dri.so`).
- Optional verified absent by default: no `flatpak`, no `/app`, no
  `sober-overlay.py`, no `/opt/apps/prismlauncher`, no steam binary.
- UI unchanged: menu entries (Roblox/Steam/Prism/Task Manager/Back Up
  Files) present exactly once; `steam`/`roblox`/`prismlauncher`
  launchers print the same "not installed" hints as before.
- Optional path: `OPTIONAL_APPS="roblox steam prism" bash install-apps.sh`
  exited 0 and deployed everything (Sober + GNOME runtime + overlay
  script, libc6 hold, steam.deb, PrismLauncher, openjdk-21); a following
  `setup.sh normal-start` created `/app/bin/sober` and applied the
  library overlay (1165 libs) while the desktop stayed up (24-bit, noVNC
  200) — identical to the master behavior.
- Validation: `OPTIONAL_APPS="bogus roblox"` fails with
  `ERROR: unknown OPTIONAL_APPS token 'bogus' (valid: roblox steam prism)`.
- Repeat runs: `setup.sh normal-start` twice + a no-arg manual run — all
  "Setup complete", state stable, desktop unaffected.
- Rebuild: `gh codespace rebuild` (~21 s, cached image) — desktop back
  up, core intact, optional payload gone (default is really core-only),
  first-start marker preserved (hooks correctly not re-run), menu
  intact, rootfs back to ~2.16 GiB.
- `tests/idempotence-test.sh`: all four lifecycle runs and both snapshot
  diffs pass; one assertion ("steam persistence dir missing") fails,
  **identically on master** — pre-existing, caused by the Codespace
  environment (user namespaces are blocked, so the test's documented
  fallback runs unisolated against the live `/home/steam/.steam` symlink
  created by the real setup). Not caused by this branch.

## Files changed on this branch

- `install-apps.sh`: core/optional split, token validation, `apt-get
  clean`; optional sections unchanged, gated.
- `Dockerfile`: `ARG OPTIONAL_APPS=""` passed to `install-apps.sh`.
- `.devcontainer/devcontainer.json`: expose the `OPTIONAL_APPS` build arg.
- `README.md`: new "Core vs optional applications (image size)" section.
- `CHANGES-perf.md` (this file).

## Limitations

- Size figures are rootfs measurements inside a Codespace, not
  `docker image inspect` (docker is unavailable in Codespaces); they
  include the identical devcontainer-feature layers in both variants.
- The optional-apps path was verified by running `install-apps.sh`
  inside the running Codespace rather than building a second image
  (creating extra branches in the shared repo was out of scope); the
  script is the same one the image build runs.
- Steam/Sober gameplay remains blocked inside Codespaces by their own
  anti-container checks (documented in README; unchanged by this branch).
