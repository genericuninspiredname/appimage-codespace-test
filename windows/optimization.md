# Windows performance recommendations for Roblox

Tuning steps for a Windows host running Roblox. Documentation only —
individual settings were not benchmarked on Windows by this branch; each
recommendation cites where it comes from. See [setup.md](setup.md) first.

## Windows-level tuning

- **Power plan:** set the power plan to "High performance" (Settings →
  System → Power) so the CPU does not down-clock mid-game; on laptops,
  plug in — most laptops throttle the GPU on battery.
- **GPU driver:** keep the AMD/NVIDIA/Intel driver current from the
  vendor's own site (not just Windows Update). Roblox relies on your GPU's
  driver for DirectX rendering.
- **Game Mode:** leave Windows **Game Mode ON** (Settings → Gaming → Game
  Mode) — it prioritizes the game's CPU/GPU allocation and pauses
  background updates during play.
- **Hardware-accelerated GPU scheduling** (Settings → Display → Graphics →
  "Change default graphics behavior"): can help on some GPUs; toggle and
  measure rather than assuming.
- **Startup/background load:** close browsers and background apps while
  playing — Roblox plus a heavy browser can exceed small-RAM machines.
- **DirectX 10 feature level is the floor:** if the client complains, update
  the GPU driver or the GPU itself is below Roblox's documented
  [minimum](https://en.help.roblox.com/hc/en-us/articles/206215488).

## In-game Roblox settings

- **Graphics quality:** Roblox's in-experience Settings → Performance offer a
  graphics quality slider and, on capable machines, manual graphics modes.
  For older/integrated-GPU machines, set graphics quality to the lowest 1–2
  notches. If the GPU is the bottleneck, lowering Windows display resolution
  helps more than only lowering in-game quality.
- **Full screen:** run the client full-screen rather than windowed —
  fewer pixels for Windows to composite.

## What to avoid

- **Third-party "FPS unlocker" tools:** Roblox's Terms of Use prohibit
  exploiting or modifying the client; historically the native in-experience
  maximum-frame-rate setting has replaced the need for unlockers on modern
  hardware. Prefer the official setting.
- **"Optimization" scripts from YouTube/reddit that edit the registry or
  kill services wholesale:** most make no measurable difference for a
  GPU-lightweight game like Roblox, and some break Windows updates.

## Frame rate

Roblox's own in-experience Settings now include a **Maximum Frame Rate**
option (up to 240 fps on supported hardware) — use that instead of any
third-party "FPS unlocker" (see "What to avoid" below). A reasonable cap
(60–120) keeps the GPU/CPU from being pinned at 100% and reduces fan noise
and heat with no visible difference on most displays.

## Measuring

Use Task Manager (Performance tab) while playing: GPU utilization near 100%
means lower graphics quality; CPU near 100% on one core means a heavier
experience or background apps. Compare before/after each change — do not
stack unmeasured tweaks.
