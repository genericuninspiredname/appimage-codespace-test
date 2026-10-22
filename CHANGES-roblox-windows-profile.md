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

Docs-only change (no scripts, no devcontainer changes). Verified in a
GitHub Codespace created on this branch (`basicLinux32gb`,
roblox/optional-windows-profile):

- **Startup:** the desktop (Fluxbox + TigerVNC + noVNC) comes up and
  answers on forwarded port 6080 with HTTP 200.
- **Idempotence / repeat-run:** `tests/idempotence-test.sh` — inside the
  Codespace the suite stops at the "FAIL: steam persistence dir missing"
  assertion during its steam fixture setup; later assertions are therefore
  not reached there. That failure **also fails on `master` in the same
  Codespace** (reproduced by checking out master there), so it is a
  pre-existing Codespaces artifact, not caused by this branch: Codespaces
  blocks user namespaces, so the test runs non-isolated and the real
  setup's `/home/steam/.steam` symlink short-circuits the fixture's
  `link_dir`. In an environment with user namespaces (the test's
  preferred mode), the full suite **passes on this branch** and passes on
  master (verified locally with `set -o pipefail`; exit code 0).
- **Rebuild:** triggered a full container rebuild on this branch — after
  it, `windows/` files are present, the branch tip is checked out, the
  desktop is up on 6080 (HTTP 200), and the first-start marker correctly
  prevents hooks from re-running.
- **Stop/start:** a full stop + start cycle preserves the checkout, the
  `windows/` docs, and the running desktop.
- **Links:** every URL in the added docs was fetched and returns 200 (the
  Roblox help-center pages return 403 to automated clients but are
  Roblox's canonical articles, confirmed via search results).
- **Accuracy pass:** after initial review, several claims were corrected —
  the VM recommendation was removed (Roblox's own error-codes page states
  VMs and cloud computers are not supported), the Sober issue quote is
  now attributed to a project contributor, the Tailscale and Sunshine
  claims were reworded to match their sources, and the frame-rate section
  now cites Roblox's official announcement. All replacement links were
  re-verified (the Microsoft and Roblox docs return 200; the Roblox help
  pages 403 to bots as noted).

No Windows host was available to this branch, so nothing Windows-specific
was executed or verified — the documents state this explicitly and make
no claim that Roblox works on Windows.
