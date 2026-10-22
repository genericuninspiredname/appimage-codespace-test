# windows/ — separate Windows host profile for Roblox

This directory documents the recommended **separate Windows profile** for
playing Roblox, for users who need Roblox to actually work. It is
documentation only — it installs nothing in the Codespace and changes no
Codespace behavior.

## Why a separate Windows host is required

**Roblox cannot run inside this Codespace.** As previously verified in this
repo (see the [README's Roblox section](../README.md#roblox) for the full
technical account), the Codespace ships the Linux Roblox runtime
[Sober](https://github.com/vinegarhq/sober), the launcher gets as far as the
onboarding UI, and then Sober's closed-source anti-tamper layer
(`libloader.so`) kills the actual Roblox game client. A Sober project
contributor states that crashes in "a virtual machine, container, or
anything else designed to automate gameplay" are
[expected behavior](https://github.com/vinegarhq/sober/issues/2475) — it
blocks automation/botting, and it cannot be worked around in this repo.
This branch did not re-run that verification; it relies on the project's
existing evidence.

Codespaces themselves run Linux only — GitHub documents that Windows and
macOS are
[not supported](https://docs.github.com/en/codespaces/overview)
as the container OS — so "run Roblox inside the Codespace" is not a possible
direction at all. Roblox's own support pages likewise state that virtual
machines and cloud computers are
[not supported](https://en.help.roblox.com/hc/en-us/articles/36639955031060-Roblox-Error-Codes)
platforms — a **physical Windows host** is the supported profile this
directory documents. (A hypervisor or cloud Windows machine is *not*
supported by Roblox and is not covered here.)

The practical answer for real Roblox gameplay is a **physical Windows
machine** — a PC you own or a second machine. No part of Roblox was
verified on Windows by anyone in this repo: **do not assume anything in this directory
was tested on Windows.** Everything here is guidance to set up and optimize
a Windows host yourself.

## What is in this directory

| File | Contents |
|------|----------|
| [setup.md](setup.md) | Windows host requirements, install steps, first-run setup |
| [remote-access.md](remote-access.md) | Connecting to the Windows host from anywhere (RDP, SSH, Sunshine/Moonlight) |
| [optimization.md](optimization.md) | Windows and in-game performance tuning for Roblox |

## Keeping Roblox data separate from Codespace data

The Windows host is a **completely separate machine** from the Codespace.
Keep it that way:

- **Roblox data stays on the Windows host.** Roblox's Windows install lives
  under `%LOCALAPPDATA%\Roblox` (i.e.
  `C:\Users\<name>\AppData\Local\Roblox`): Roblox's own docs reference
  that root for its executables — the
  [Studio CLI docs](https://create.roblox.com/docs/studio/command-line-interface)
  document `%LOCALAPPDATA%\Roblox\Versions\...`, and the
  [bundled-installer guide](https://create.roblox.com/docs/education/support/creating-bundled-installers)
  points both Studio and the player at the same location; Roblox's
  [uninstall instructions](https://en.help.roblox.com/hc/en-us/articles/203312980-How-to-Uninstall-Roblox)
  also direct you to delete the Roblox folder under `AppData\Local`. Nothing
  about this location has any relationship to the Codespace's `/workspaces`
  or the `desktop-data` branch.
- **Never push Roblox data to this repo.** The repo's Codespace tools write to
  the `desktop-data` branch: plain **Back Up Files** commits the Codespace's
  `~/Files` (documents), and the encrypted profile tool additionally packs
  the Codespace's browser profile. Roblox saves, screenshots, recordings, and
  the Roblox install folder live on the Windows host and should be backed up
  with a Windows backup tool — `desktop-backup` / `desktop-profile` will
  never see the Windows machine and must not be pointed at it.
- **Keep accounts/credentials separate.** Signing into Roblox happens on
  the Windows host in the Roblox app; the Codespace's browser profile and
  its stored credentials are separate and should stay that way.
- **The Codespace stays as-is.** This branch adds no scripts, no devcontainer
  changes, and no behavior changes — only these documents.

## Status summary (what this is, honestly)

| Claim | Status |
|-------|--------|
| Linux Sober blocked by anti-container protections in Codespaces | Verified (see [README](../README.md#roblox)) |
| Roblox works on a Windows host described here | **Not verified on Windows — documentation only** |
| Remote access methods (RDP/SSH/Sunshine) work as described | Documented from vendor documentation; not verified on a Windows host |

If you set up a Windows host and verify anything in these documents, please
update this table with your results.
