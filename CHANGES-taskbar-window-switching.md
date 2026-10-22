# Changes: taskbar and window switching (ui/taskbar-and-window-switching)

Goal: improve the Fluxbox taskbar and window-switching experience through
noVNC — taskbar readability, active/inactive window distinction, clear
workspace switching, and reliable keyboard shortcuts that work from a
browser. No frontend framework; the desktop menu is untouched.

## What changed

One new setup module (merge-safe per `hooks/README.md`: a new numbered
module instead of edits to shared ones):

- `.devcontainer/modules/65-taskbar-window-switching.sh` — appends
  managed `# >>> taskbar-switch-* >>>` blocks to the fluxbox files that
  `60-fluxbox.sh` owns (fluxbox applies the last occurrence of a duplicate
  resource, so the refinements below win):
  - `~/.fluxbox/overlay`: `*.font: sans-10` (the taskbar's height follows
    its font, so labels get bigger and the bar easier to click); focused
    window gets a blue accent titlebar/handle/grip with white text, unfocused
    windows are muted dark grey; the focused taskbar button uses the same
    blue accent so the active window is obvious in both places.
  - `~/.fluxbox/keys`: `Ctrl+Alt+Left/Right` → prev/next workspace and
    `Ctrl+Alt+Shift+Left/Right` → send the active window to the prev/next
    workspace. Browsers pass Ctrl+Alt+arrows through to noVNC (unlike
    Alt+Tab), so these are reliable in a browser session.
  - `~/.fluxbox/init`: the iconbar mode is set to its window-pattern form
    `{static groups} (workspace)` — the bare word `Workspace` is not a valid
    pattern, so fluxbox showed windows from ALL workspaces in the taskbar,
    which made workspace switching muddy; with the pattern the taskbar shows
    only the current workspace's windows. Also `allowRemoteActions: true`
    so `fluxbox-remote restart` actually works — without it the config
    re-apply that setup performs on every start (70-diagnostics.sh) was
    silently ignored, and taskbar/key changes only took effect after a full
    codespace stop/start.
  - `~/.fluxbox/SHORTCUTS`: documents the new bindings (the block is
    re-appended after 60's rewrite on every setup run).

Existing `Alt+`` window cycling, `Alt+1..4` workspace jumps and the whole
desktop menu from earlier work are preserved unchanged.

## Testing

- `tests/idempotence-test.sh` (unchanged) — passes with the new module in
  place: 4 setup runs leave state byte-identical; managed blocks appear
  exactly once; user edits to the keys/menu files survive.
- `tests/taskbar-test.sh` — runs the coordinator twice and verifies the
  generated fluxbox files: new managed blocks (overlay/keys/init/SHORTCUTS)
  exactly once, the font size, the focus/unfocus colors, the key bindings,
  the iconbar pattern and allowRemoteActions in init, and that the earlier
  menu / keys / overlay blocks survive.
- `tests/codespace-verify.sh` — run inside the Codespace on this branch
  (it installs xdotool itself if missing and accepts both Xvnc and
  Xtigervnc). It checks the generated config, opens several windows
  (Mousepad, terminal, file manager) and verifies through the X server —
  the same input path noVNC's websocket keyboard events feed — that
  Alt+` cycles windows, Ctrl+Alt+Left/Right switches workspaces,
  Ctrl+Alt+Shift+arrows move the active window between workspaces, the
  root menu is still bound, a repeat `setup.sh normal-start` run is
  idempotent (config byte-identical), and `fluxbox-remote restart` keeps
  every window open.
- Visual verification via screenshots inside the Codespace: with several
  windows open the taskbar labels are readable, the focused window's
  titlebar and taskbar button are blue while inactive ones are dark grey,
  the workspace name indicator updates on switching (Main → Web → Extra),
  and with the iconbar fix the taskbar buttons follow the current
  workspace (empty on a workspace with no windows). The desktop menu still
  opens via right-click. noVNC on port 6080 serving.

## Limitations

- Alt+Tab is still captured by browsers/OSes; Alt+` remains the documented
  noVNC window-cycling key.
- The font name `sans-10` resolves through fontconfig to the default
  sans-serif (DejaVu Sans in this image).
- The key-injection tests go through the X server, which is the same input
  path noVNC uses, but they cannot prove a specific browser passes every
  combo (e.g. some browsers reserve Ctrl+Alt+arrows on some platforms).
- TigerVNC's session opens a small "VNC config"/"xmessage" dialog pair on
  each desktop start; they appear as taskbar buttons until closed. They
  come from the VNC layer, not from this branch.
