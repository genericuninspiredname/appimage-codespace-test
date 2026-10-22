# CHANGES — roblox/optional-windows-profile

Branch goal: document and prepare a separate Windows profile for Roblox
use, keeping it fully separate from the Linux Codespace.

## What this branch adds

- `windows/` directory — documentation only, no scripts, no devcontainer
  changes, no behavior changes to the Codespace:
  - `windows/README.md` — why a separate Windows host is required (Sober's
    anti-tamper blocks the Roblox client in all containers, verified in
    this repo; Codespaces are Linux-only), data-separation rules, and an
    honest status table of what this branch verified (nothing on Windows)
    versus documented.
  - `windows/setup.md` — supported Windows host requirements (from
    Roblox's official documentation), install steps, first-run checks.
  - `windows/remote-access.md` — remote connection guidance: RDP over a
    private tunnel (Tailscale), Sunshine/Moonlight for gameplay
    streaming, SSH for admin; with the security rule to never expose
    RDP/3389 or streaming UIs to the internet.
  - `windows/optimization.md` — Windows-level tuning (power plan, Game
    Mode, GPU drivers), in-game Roblox settings, the native Maximum Frame
    Rate setting instead of third-party FPS unlockers, and what to avoid.
- `README.md` — short pointer in the Roblox section to the Windows
  profile docs.

## What this branch deliberately does NOT do

- It does not claim Roblox works anywhere. Roblox on a Windows host is
  documentation-only; no Windows host was available to this branch, so
  nothing in `windows/` was executed or verified on Windows. Every doc
  states this explicitly.
- It does not touch the Codespace setup, modules, hooks, or scripts. The
  `roblox` Linux launcher and Sober remain exactly as on master.
- It does not merge, rebase, or modify any other branch.

## Conflict audit of other branches' DONE commits

Inspected every commit named exactly `DONE` reachable in the repo at the
time of this work (`2610195`, `c0eeca5`, `f0783d8`, `a0067d5`, `b7cc933`,
`4292b58`):

- `2610195`, `f0783d8`, `a0067d5`, `b7cc933` — already contained in
  `master` or empty commits; their content is the base this branch starts
  from. No conflict.
- `c0eeca5` (steam-prismlauncher) — adds the Steam/Minecraft README
  sections and a screenshot; not merged to master at this time. This
  branch's README edit is inside the Roblox section (before the Steam
  heading), different lines, and adds no files it touches. No conflict.
- `4292b58` (perf/codespace-cost-controls) — README edit is in the
  "Resolution" bullet (Use-the-desktop section) plus perf-tools module
  and CHANGES file. This branch's README edit is in the Roblox section.
  No conflict.

## Testing

Docs-only change. Verified inside a Codespace on this branch (see branch
commit message for details): `windows/` files present and readable,
README links resolve, `tests/idempotence-test.sh` passes (setup unchanged
and safe to re-run), and a full container rebuild + restart shows no
regressions from this branch. No Windows host was available, so nothing
Windows-specific was executed.
