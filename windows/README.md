# windows/ — separate Windows host profile for Roblox

This directory documents the recommended **separate Windows profile** for
playing Roblox, for users who need Roblox to actually work. It is
documentation only — it installs nothing in the Codespace and changes no
Codespace behavior.

## Why a separate Windows host is required

**Roblox cannot run inside this Codespace — or any Linux container.** The
Codespace ships the Linux Roblox runtime
[Sober](https://github.com/vinegarhq/sober), and the launcher gets as far as
the onboarding UI, but Sober's closed-source anti-tamper layer
(`libloader.so`) deliberately crashes the Roblox game client whenever it
detects it is running inside a container or VM. This is intended behavior by
Sober's maintainers, who confirm that crashes in "a virtual machine,
container, or anything else designed to automate gameplay" are
[expected](https://github.com/vinegarhq/sober/issues/2475) — it blocks
automation/botting, and it cannot be worked around in this repo. See the
[README's Roblox section](../README.md#roblox) for the full technical
account of what was verified inside the Codespace.

Codespaces themselves run Linux only — GitHub documents that Windows and
macOS are
[not supported](https://docs.github.com/en/codespaces/developing-in-a-codespace/setting-your-user-preferences-for-codespaces#accessibility-settings)
as the container OS — so "run Roblox inside the Codespace" is not a possible
direction at all.

The practical answer for real Roblox gameplay is a **real Windows
machine**: a physical PC you own, a second machine, or a Windows VM on
hardware you control with a real hypervisor (VMware, Hyper-V, VirtualBox)
where you can assess the risk of the same anti-container detection yourself.
No part of Roblox was verified working by this branch: **do not assume
anything in this directory was tested on Windows.** Everything here is
guidance to set up and optimize a Windows host yourself.

## What is in this directory

| File | Contents |
|------|----------|
| [setup.md](setup.md) | Windows host requirements, install steps, first-run setup |
| [remote-access.md](remote-access.md) | Connecting to the Windows host from anywhere (RDP, SSH, Sunshine/Moonlight) |
| [optimization.md](optimization.md) | Windows and in-game performance tuning for Roblox |

## Keeping Roblox data separate from Codespace data

The Windows host is a **completely separate machine** from the Codespace.
Keep it that way:

- **Roblox data stays on the Windows host.** The Roblox launcher and player
  install and store their data under `%LOCALAPPDATA%\Roblox` (i.e.
  `C:\Users\<name>\AppData\Local\Roblox`) on Windows — see the
  [Launcher CLI docs](https://create.roblox.com/docs/studio/launcher-CLI)
  for the launcher commands that operate on that install, and
  [Bloxstrap's documentation](https://github.com/bloxstraplabs/bloxstrap/wiki/)
  for the same layout. Nothing about this location has any relationship to
  the Codespace's `/workspaces` or the `desktop-data` branch.
- **Never push Roblox data to this repo.** The repo's backup branches
  (`desktop-data`) are for the Codespace's `~/Files` documents only. Roblox
  saves, screenshots, recordings, and the Roblox install folder live on the
  Windows host and should be backed up with a Windows backup tool, not with
  this repo's Codespace tooling (`desktop-backup` / `desktop-profile` will
  never see the Windows machine and must not be pointed at it).
- **Keep accounts/credentials separate.** Signing into Roblox happens on
  the Windows host in the Roblox app; the Codespace's browser profile and
  its stored credentials are separate and should stay that way.
- **The Codespace stays as-is.** This branch adds no scripts, no devcontainer
  changes, and no behavior changes — only these documents.

## Status summary (what this is, honestly)

| Claim | Status |
|-------|--------|
| Linux Sober blocked by anti-container protections in Codespaces | Verified (see [README](../README.md#roblox)) |
| Roblox works on a Windows host described here | **Not verified by this branch — documentation only** |
| Remote access methods (RDP/SSH/Sunshine) work as described | Documented from vendor documentation; not verified on a Windows host by this branch |

If you set up a Windows host and verify anything in these documents, please
update this table with your results.
