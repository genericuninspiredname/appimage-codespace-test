# Windows host setup for Roblox

Steps and requirements for preparing a Windows machine to play Roblox.
Documentation only — nothing here was verified on Windows by this branch.

## Supported Windows host requirements

Roblox's official requirements for the Windows client are minimal — Roblox
publishes a
[chart of supported platforms](https://en.help.roblox.com/hc/en-us/articles/206215488)
on its help site; the current Windows player requirements per that page and
Roblox's system-requirements documentation are:

| Component | Roblox player requirement | Notes |
|-----------|---------------------------|-------|
| OS | Windows 10 / Windows 11 (64-bit) | 32-bit Windows is not supported |
| CPU | 64-bit processor, 1.6 GHz or faster, made 2005 or later | Any modern x86-64 CPU qualifies |
| RAM | 1 GB minimum | Realistic play with browser/voice: 8 GB recommended |
| Storage | ~300 MB for the launcher + extra per-experience content | Any SSD is far beyond this |
| GPU | Any card with DirectX 10 feature level | Integrated graphics (Intel/AMD iGPU) are fine for casual play; a discrete GPU is needed for consistently high graphics levels |
| Internet | Broadband; Roblox's guidance is 4–8 Mb/s | Latency matters more than raw bandwidth for play |
| Account | Roblox account, created at roblox.com or in the app | Sign-in happens on the Windows host, not the Codespace |

For **Roblox Studio** (only if you develop, not just play), the requirements
are higher: Roblox documents a minimum of Windows 10, 3 GB RAM (8 GB
recommended), and a 1600x900 or larger display — see
[Studio's system requirements](https://create.roblox.com/docs/studio/setup).

Nothing about playing Roblox requires Windows Pro or a license beyond the
Windows install itself — but **remote desktop hosting (RDP) does require
Windows 10/11 Pro**, covered in [remote-access.md](remote-access.md).

## Install steps

1. Sign in to Windows and confirm it is activated and up to date (Settings →
   Windows Update).
2. Install GPU drivers from the GPU vendor (AMD/NVIDIA/Intel), not just
   whatever Windows Update picked — vendors' own driver packages fix
   rendering issues more often.
3. Download the Roblox installer from
   [roblox.com/download](https://www.roblox.com/download) and run it. The
   player installs itself into `%LOCALAPPDATA%\Roblox` on first launch of
   any experience; there is no traditional "Programs" install.
4. Launch a experience from the website or the app, sign in with your Roblox
   account, and verify the game runs.
5. Optional: install [Bloxstrap](https://github.com/bloxstraplabs/bloxstrap)
   (an open-source Roblox launcher wrapper) if you want per-experience
   graphics and flag management — third-party launchers are community tools,
   use at your own discretion.

## First-run checks

- Verify the game renders and audio works (test in a quiet experience
  first).
- Set expectations: integrated graphics on a laptop will run Roblox at low
  graphics levels; that is normal, not a setup error.
- Back up nothing to the Codespace — Roblox data lives in
  `%LOCALAPPDATA%\Roblox` on this machine and stays here (see the
  [data-separation rules](README.md#keeping-roblox-data-separate-from-codespace-data)).
