# Remote connection to the Windows host

Ways to reach your Windows Roblox host when you are not sitting at it, and
how to do so without exposing it to the internet. Documentation only —
nothing here was verified on Windows by this branch; each method cites its
vendor's documentation.

## Security rule first

**Do not expose RDP (port 3389) or any remote-access port directly to the
internet.** RDP servers open to the internet are constantly scanned and
brute-forced. Every option below keeps the host reachable only through an
encrypted tunnel or a direct connection you initiate.

## Option 1 — RDP over a private tunnel (recommended for full desktop use)

Windows 10/11 **Pro** can host a native RDP server ("Remote Desktop");
**Windows Home cannot host RDP** — Microsoft documents how to
[enable and use Remote Desktop](https://support.microsoft.com/en-us/windows/how-to-use-remote-desktop-5cfe0d66-c53b-4bc3-a2b1-27b6a38672a4)
(Windows Settings → System → Remote Desktop → toggle on) and notes the
Home/Pro distinction there. On a Mac, Microsoft's
[Windows App / Remote Desktop client](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/clients/remote-desktop-clients)
connects to it; Windows also ships its own built-in Remote Desktop
Connection client.

To reach it safely from outside your LAN:

- **Tailscale** (recommended): install it on both the Windows host and your
  remote device, sign both into the same tailnet. Tailscale assigns each
  machine a private 100.x.y.z address and the connection is
  [WireGuard-encrypted end to end](https://tailscale.com/kb/1136/tailscale-vs-vpn);
  the RDP port never needs to be port-forwarded. See Tailscale's
  [Windows RDP guide](https://tailscale.com/kb/1273/tailscale-windows-rdp).
- Alternative: any WireGuard or OpenVPN tunnel you control, then RDP inside
  the tunnel.

From the Codespace you could also reach the host if it is on the same
private network as you (e.g. via your own VPN/Tailscale subnet), but the
Codespace has no special relationship with your Windows machine — connect
from wherever you are, not "through" the Codespace.

## Option 2 — Sunshine/Moonlight (best for streaming gameplay)

RDP is fine for setup and admin, but it is not built for smooth 3D game
streaming. For playing Roblox remotely with low latency:

- Install [Sunshine](https://github.com/LizardByte/Sunshine) (open-source
  game-stream server) on the Windows host.
- Pair a [Moonlight](https://moonlight-stream.org) client (Windows, macOS,
  iOS, Android, tvOS) and stream the Roblox window or the whole desktop.
- Moonlight is built on the same protocol as NVIDIA GameStream, works with
  NVIDIA/AMD/Intel GPUs and even software capture, and the
  [setup guide](https://moonlight-stream.org/docs/) walks through pairing
  and settings (resolution, frame rate, bitrate — tune these to your
  network).

Sunshine's web UI must not be left exposed to the internet either — pair it
over the LAN or your tailnet, and see the project's
[security notes](https://github.com/LizardByte/Sunshine#security).

## Option 3 — SSH (for admin, not gameplay)

Windows 10/11 ships an optional OpenSSH server (Settings → Apps → Optional
Features → OpenSSH Server). It is useful for scripts/updates, but it is a
terminal — you cannot play Roblox over it. Microsoft documents
[installing OpenSSH on Windows](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_usefull-windows-server);
restrict it to key auth and your tailnet if you enable it.

## What does not work: playing from inside the Codespace

The Codespace's noVNC desktop cannot reach your Windows host's audio, GPU,
or low-latency input. You can open the Codespace desktop and use its Firefox
to visit the Roblox website, but actual gameplay of the native client
happens on the Windows host with one of the methods above — and remember
that the Linux Sober client in the Codespace is blocked by anti-container
protections (see the [README](../README.md#roblox)).
