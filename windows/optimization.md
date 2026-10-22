# Windows performance recommendations for Roblox

Tuning steps for a Windows host running Roblox. Documentation only —
individual settings were not benchmarked on Windows for this repo; each
recommendation cites where it comes from. See [setup.md](setup.md) first.

## Windows-level tuning

- **Power plan:** compare the available power modes (Settings → System →
  Power) while plugged in and use whichever gives the best measured result;
  laptops in particular may throttle the GPU on battery. No specific plan
  was measured for this repo.
- **GPU driver:** keep the AMD/NVIDIA/Intel driver current from the
  vendor's own site (not just Windows Update). Roblox relies on your GPU's
  driver for DirectX rendering.
- **Game Mode:** leave Windows **Game Mode ON** (Settings → Gaming → Game
  Mode) — Microsoft's
  [Game Mode documentation](https://support.microsoft.com/en-us/help/4028293/windows-using-game-mode-on-your-pc)
  says it "helps achieve a more stable frame rate depending on the specific
  game and system" and suspends Windows Update driver installs and
  restart notifications during play. It is on by default; leave it that
  way unless you have a measured reason not to.
- **Hardware-accelerated GPU scheduling** (Settings → Display → Graphics →
  "Change default graphics behavior"): Microsoft introduced it to reduce
  GPU scheduling latency (see the
  [DirectX team's announcement](https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/));
  whether it helps Roblox on your GPU is not documented — toggle and measure
  rather than assuming.
- **Startup/background load:** close browsers and background apps while
  playing — Roblox plus a heavy browser can exceed small-RAM machines.
- **DirectX 10 feature level is the floor:** if the client complains, update
  the GPU driver or the GPU itself is below Roblox's documented
  [minimum](https://en.help.roblox.com/hc/en-us/articles/203312800-Computer-Hardware-Operating-System-Requirements).

## In-game Roblox settings

- **Graphics quality:** the in-experience Settings menu (Esc → Settings)
  exposes a graphics quality slider and, on capable machines, manual
  graphics modes. For older/integrated-GPU machines, set graphics quality
  to the lowest 1–2 notches and measure.
- **Full screen:** compare full-screen and windowed modes on your machine;
  use whichever gives better measured responsiveness and stability. This
  branch has not benchmarked either mode.

## What to avoid

- **Third-party "FPS unlocker" tools:** Roblox's own announcement of the
  in-game Maximum Frame Rate setting recommends using the setting instead
  of external unlockers, noting that unlockers change an internal client
  flag that was never intended as a stable public API and could change
  without prior notice (see the
  [announcement](https://devforum.roblox.com/t/introducing-the-maximum-framerate-setting/2995965)).
  Prefer the official setting; whether unlockers violate the Terms of Use
  is not for this doc to rule on.
- **"Optimization" scripts from YouTube/reddit that edit the registry or
  kill services wholesale:** avoid unreviewed registry or service
  modifications — unvetted changes can break Windows updates, and none
  were reviewed for this repo.

## Frame rate

Roblox's official client frame-rate cap is 60 FPS, and users can raise it
to up to 240 FPS on Windows (per Roblox's
[performance documentation](https://create.roblox.com/docs/performance-optimization/identify)).
The in-experience Settings menu exposes a **Maximum Frame Rate** option —
values Default/60/120/144/240 per Roblox's
[announcement](https://devforum.roblox.com/t/introducing-the-maximum-framerate-setting/2995965).
Try a lower Maximum Frame Rate setting and compare utilization,
temperature, noise, and smoothness — no performance or thermal improvement
was measured for this repo.

## Measuring

Use Task Manager (Performance tab) while playing: GPU utilization near 100%
means lower graphics quality; CPU near 100% on one core means a heavier
experience or background apps. Compare before/after each change — do not
stack unmeasured tweaks.
