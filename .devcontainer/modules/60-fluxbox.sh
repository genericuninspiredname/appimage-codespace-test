#!/usr/bin/env bash
# 60-fluxbox.sh - Fluxbox settings: wallpaper, init, overlay, keys, shortcuts.
# Split from setup.sh (section 5); behavior unchanged.
# Uses: HOMEDIR REPO_DIR.
# ---------------------------------------------------------------------------
# 5. Desktop polish: taskbar, window switching, wallpaper, WebGL. All managed
#    blocks/files, replaced on every run so upgrades apply cleanly.
# ---------------------------------------------------------------------------
FLUXDIR="$HOMEDIR/.fluxbox"

# Wallpaper (copied from the repo so it survives ~/.fluxbox being persisted)
mkdir -p "$FLUXDIR/backgrounds"
[ -f "$REPO_DIR/assets/wallpaper.png" ] && \
  cp -f "$REPO_DIR/assets/wallpaper.png" "$FLUXDIR/backgrounds/wallpaper.png"

# --- init: taskbar layout + workspaces (managed block at the END of the file:
# fluxbox keeps the last occurrence of a duplicate resource, so our values
# must come after any earlier ones) ---
INIT="$FLUXDIR/init"
init_block="# >>> desktop-init >>>
session.screen0.workspaces: 4
session.screen0.workspaceNames: Main, Web, Extra, Four
session.screen0.workspacewarping: true
session.screen0.toolbar.visible: true
session.screen0.toolbar.layer: Dock
session.screen0.toolbar.placement: BottomCenter
session.screen0.toolbar.autoHide: false
session.screen0.toolbar.tools: RootMenu, workspacename, prevworkspace, nextworkspace, iconbar, systemtray, prevwindow, nextwindow, clock
session.screen0.iconbar.mode: Workspace
session.screen0.iconbar.usePixmap: true
session.screen0.iconbar.alignment: Relative
session.screen0.focusNewWindows: true
session.screen0.focusLastWindow: true
session.screen0.strftimeFormat: %a %b %d %l:%M %p
session.styleOverlay: $FLUXDIR/overlay
# <<< desktop-init <<<"
if [ -f "$INIT" ]; then
  awk -v block="$init_block" '
    /^# >>> desktop-init >>>/ { inb = 1; next }
    /^# <<< desktop-init <<</ { inb = 0; next }
    inb { next }
    { print }
    END { print block }
  ' "$INIT" > "$INIT.new" && mv "$INIT.new" "$INIT"
else
  printf '%s\n' "$init_block" > "$INIT"
fi

# Style overlay: wallpaper + readable taskbar labels (the qnx-photon style
# ships no iconbar colors, so window titles wash out without these).
# Managed block: fluxbox also writes user style changes to this file.
OVERLAY="$FLUXDIR/overlay"
overlay_block="# >>> desktop-overlay >>>
background: aspect
background.pixmap: $FLUXDIR/backgrounds/wallpaper.png
# --- dark taskbar theme ---
toolbar: flat gradient vertical
toolbar.color: rgb:28/28/3A
toolbar.colorTo: rgb:1C/1C/29
toolbar.textColor: rgb:C8/C8/D8
toolbar.bevelWidth: 1
toolbar.clock: flat solid
toolbar.clock.color: rgb:1E/1E/2C
toolbar.clock.textColor: rgb:9A/9A/B5
toolbar.workspace: parentrelative
toolbar.workspace.textColor: rgb:C0/C0/D4
toolbar.button: parentrelative
toolbar.button.picColor: rgb:9A/9A/B5
toolbar.button.pressed: parentrelative
toolbar.button.pressed.picColor: rgb:D0/D0/E0
toolbar.iconbar.empty: flat solid
toolbar.iconbar.empty.color: rgb:1E/1E/2C
toolbar.iconbar.focused: flat gradient vertical
toolbar.iconbar.focused.color: rgb:3E/3E/5A
toolbar.iconbar.focused.colorTo: rgb:2C/2C/42
toolbar.iconbar.focused.textColor: rgb:F0/F0/FA
toolbar.iconbar.focused.borderColor: rgb:62/62/94
toolbar.iconbar.focused.borderWidth: 1
toolbar.iconbar.unfocused: flat solid
toolbar.iconbar.unfocused.color: rgb:22/22/30
toolbar.iconbar.unfocused.textColor: rgb:85/85/9C
# --- dark root menu ---
menu.title: flat gradient vertical
menu.title.color: rgb:2E/2E/44
menu.title.colorTo: rgb:20/20/30
menu.title.textColor: rgb:D8/D8/E8
menu.frame: flat solid
menu.frame.color: rgb:24/24/33
menu.frame.textColor: rgb:C4/C4/D4
menu.frame.disableColor: rgb:5C/5C/6C
menu.hilite: flat solid
menu.hilite.color: rgb:3D/3D/5E
menu.hilite.textColor: rgb:EE/EE/F8
# <<< desktop-overlay <<<"
if [ -f "$OVERLAY" ]; then
  awk -v block="$overlay_block" '
    /^# >>> desktop-overlay >>>/ { inb = 1; next }
    /^# <<< desktop-overlay <<</ { inb = 0; next }
    inb { next }
    { print }
    END { print block }
  ' "$OVERLAY" > "$OVERLAY.new" && mv "$OVERLAY.new" "$OVERLAY"
else
  printf '%s\n' "$overlay_block" > "$OVERLAY"
fi

# --- keys: window switching that works through noVNC (the browser/OS usually
# captures Alt+Tab, so Alt+` is the practical binding there) ---
KEYS="$FLUXDIR/keys"
keys_block="# >>> desktop-keys >>>
# Alt+\` cycles windows too: browsers/OSes usually capture Alt+Tab when the
# desktop is used through noVNC, and Alt+\` is not intercepted.
Mod1 grave :NextWindow {groups} (workspace=[current])
Mod1 Shift grave :PrevWindow {groups} (workspace=[current])
# Alt+1..4 jump straight to a workspace
Mod1 1 :Workspace 1
Mod1 2 :Workspace 2
Mod1 3 :Workspace 3
Mod1 4 :Workspace 4
# Ctrl+Alt+Delete opens the task manager, like a normal desktop
Control Mod1 Delete :ExecCommand tilix -e htop
# <<< desktop-keys <<<"
if [ ! -f "$KEYS" ]; then
  # First run: fluxbox would create this from /etc/X11/fluxbox/keys at first
  # start (postCreate runs before that); write that default plus our block.
  # Drop the stock Ctrl+Alt+Del :Exit binding (it would kill the desktop, and
  # a duplicate would make fluxbox reject our task-manager binding).
  grep -v '^Control Mod1 Delete' /etc/X11/fluxbox/keys > "$KEYS" 2>/dev/null || true
  [ -s "$KEYS" ] || printf 'OnDesktop Mouse3 :RootMenu\n' > "$KEYS"
  printf '%s\n' "$keys_block" >> "$KEYS"
elif ! grep -q '^# >>> desktop-keys >>>' "$KEYS"; then
  grep -v '^Control Mod1 Delete' "$KEYS" > "$KEYS.new" && mv "$KEYS.new" "$KEYS"
  printf '%s\n' "$keys_block" >> "$KEYS"
else
  awk '
    /^# >>> desktop-keys >>>/ { inb = 1; next }
    /^# <<< desktop-keys <<</ { inb = 0; next }
    inb { next }
    # drop any stock Ctrl+Alt+Del binding outside our block (see above)
    /^Control Mod1 Delete/ && !inb { next }
    { print }
  ' "$KEYS" > "$KEYS.new" && mv "$KEYS.new" "$KEYS"
  printf '%s\n' "$keys_block" >> "$KEYS"
fi

# --- shortcuts cheat sheet (opened from the menu) ---
cat > "$FLUXDIR/SHORTCUTS" <<'DOC'
Keyboard shortcuts
==================

Switching windows
  Alt+Tab / Alt+Shift+Tab    cycle windows (needs a real VNC client;
                             browsers usually capture Alt+Tab)
  Alt+` (backtick)          cycle windows - use this through noVNC
  Alt+Shift+`                cycle backwards
  Taskbar arrows / scroll    click the < > buttons or scroll the taskbar

Workspaces (4)
  Ctrl+Alt+Left / Right      previous / next workspace
  Scroll on the desktop      previous / next workspace
  Alt+1 .. Alt+4             jump to workspace 1-4
  Super+Left / Right         send window to prev/next workspace
  Ctrl+Super+Left / Right    take window with you

Windows
  Alt+F2                     run dialog (or menu: Run Program...)
  Alt+F4 / Alt+F9            close / minimize
  Alt+F10 / Alt+F11          maximize / fullscreen
  Alt+Space                  window menu
  Alt+drag                   move; Alt+right-drag resizes
  Ctrl+drag titlebar         onto another window to group them as tabs
  Double-click titlebar      shade the window

System
  Ctrl+Alt+Delete            task manager (htop; also in the menu)
DOC
