#!/usr/bin/env bash
# 65-taskbar-window-switching.sh - taskbar readability, active/inactive window
# contrast, and workspace/window-switching keys that work through noVNC.
#
# Branch ui/taskbar-and-window-switching. Follows the merge-safe convention
# from hooks/README.md (a new module instead of editing shared ones):
# 60-fluxbox.sh keeps its own managed blocks, this module appends separate
# '# >>> taskbar-switch-* >>>' blocks to the same fluxbox files. Fluxbox
# applies the LAST occurrence of a duplicate resource, so the values below
# deliberately refine the base theme from 60-fluxbox.sh. Runs after it in
# lexical order on every setup run (first start, restart, rebuild).
# Uses: HOMEDIR.
# ---------------------------------------------------------------------------
FLUXDIR="$HOMEDIR/.fluxbox"

# Managed-block updater: replace the block between the markers, or append it.
# (Same technique as 60-fluxbox.sh; keeps repeat runs idempotent.)
set_block() { # set_block <file> <marker> <block-content>
  local file="$1" marker="$2" block="$3"
  if [ -f "$file" ] && grep -q "^# >>> ${marker} >>>" "$file"; then
    awk -v marker="$marker" -v block="$block" '
      $0 == "# >>> " marker " >>>" { inb = 1; next }
      $0 == "# <<< " marker " <<<" { inb = 0; next }
      inb { next }
      { print }
      END { print block }
    ' "$file" > "$file.new" && mv "$file.new" "$file"
  else
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$block" >> "$file"
  fi
}

# --- 1. Style overlay additions: readable fonts + active/inactive contrast.
# The taskbar's height follows its font, so sans-10 also makes the taskbar
# taller and its buttons easier to read and click. The focused window gets a
# blue accent titlebar; unfocused windows are muted dark grey, so the active
# window is unmistakable. The focused taskbar button uses the same blue so
# titlebar and taskbar agree on which window is active.
# (Overlay values below override 60-fluxbox.sh's purple focused button -
# last occurrence wins in fluxbox.)
OVERLAY="$FLUXDIR/overlay"
overlay_block="# >>> taskbar-switch-overlay >>>
# --- readable fonts (taskbar height follows its font) ---
*.font: sans-10
# --- active window: blue accent ---
window.title.focus: flat gradient vertical
window.title.focus.color: rgb:3A/5C/8E
window.title.focus.colorTo: rgb:27/3E/62
window.label.focus.textColor: rgb:FF/FF/FF
window.button.focus: parentrelative
window.button.focus.picColor: rgb:C8/D8/F0
window.button.pressed: parentrelative
window.button.pressed.picColor: rgb:FF/FF/FF
window.handle.focus: flat solid
window.handle.focus.color: rgb:27/3E/62
window.grip.focus: flat solid
window.grip.focus.color: rgb:3A/5C/8E
window.frame.focusColor: rgb:3A/5C/8E
# --- inactive windows: muted dark grey ---
window.title.unfocus: flat solid
window.title.unfocus.color: rgb:1F/1F/2C
window.label.unfocus.textColor: rgb:8A/8A/A0
window.button.unfocus: parentrelative
window.button.unfocus.picColor: rgb:6E/6E/84
window.handle.unfocus: flat solid
window.handle.unfocus.color: rgb:1A/1A/26
window.grip.unfocus: flat solid
window.grip.unfocus.color: rgb:22/22/30
window.frame.unfocusColor: rgb:2A/2A/3A
# --- taskbar: focused button matches the focused titlebar accent ---
toolbar.iconbar.focused: flat gradient vertical
toolbar.iconbar.focused.color: rgb:3A/5C/8E
toolbar.iconbar.focused.colorTo: rgb:27/3E/62
toolbar.iconbar.focused.textColor: rgb:FF/FF/FF
toolbar.iconbar.focused.borderColor: rgb:6E/9E/D8
toolbar.iconbar.focused.borderWidth: 1
# <<< taskbar-switch-overlay <<<"
set_block "$OVERLAY" taskbar-switch-overlay "$overlay_block"

# --- 2. Key bindings that reach fluxbox through a browser noVNC session.
# Browsers pass Ctrl+Alt+arrows to the remote desktop (they do not reserve
# them), unlike Alt+Tab which the browser/OS captures - Alt+` from
# 60-fluxbox.sh stays the window-cycling fallback. Alt+1..4 (also from
# 60-fluxbox.sh) remain the no-argument workspace jumps. These bindings are
# appended after the stock ones, so they also guarantee the commands are
# bound even if the stock keys file changes.
KEYS="$FLUXDIR/keys"
keys_block='# >>> taskbar-switch-keys >>>
# Workspace switching (browsers do not capture Ctrl+Alt+arrows; through
# noVNC these reach fluxbox. Alt+1..4 above are the no-arrow fallback.)
Control Mod1 Left :PrevWorkspace
Control Mod1 Right :NextWorkspace
# Send the active window to the previous/next workspace
Control Mod1 Shift Left :SendToPrevWorkspace
Control Mod1 Shift Right :SendToNextWorkspace
# <<< taskbar-switch-keys <<<'
set_block "$KEYS" taskbar-switch-keys "$keys_block"

# --- 3. init additions (managed block at the END of init: fluxbox keeps
# the last occurrence of a duplicate resource, so these must come after both
# the desktop-init block and any lines fluxbox itself appends when it saves):
#   - iconbar.mode must be the window-pattern form '{static groups} (workspace)'.
#     The bare word 'Workspace' (used by the desktop-init block) is not a
#     valid pattern, and fluxbox falls back to showing windows from ALL
#     workspaces in the taskbar, which makes workspace switching muddy.
#   - allowRemoteActions lets 'fluxbox-remote restart' work, so setup can
#     re-apply config to a running desktop (70-diagnostics.sh) and the
#     taskbar/keys take effect immediately after a repeat setup run,
#     without a full codespace restart.
INIT="$FLUXDIR/init"
init_block="# >>> taskbar-switch-init >>>
session.screen0.iconbar.mode: {static groups} (workspace)
session.screen0.allowRemoteActions: true
# <<< taskbar-switch-init <<<"
set_block "$INIT" taskbar-switch-init "$init_block"

# --- 4. Shortcut cheat sheet: document the additions (60-fluxbox.sh rewrites
# the whole file each run, then this block is re-appended after it, so the
# sheet stays correct across repeat runs).
SHORTCUTS="$FLUXDIR/SHORTCUTS"
shortcuts_block='# >>> taskbar-switch-shortcuts >>>
Taskbar & window focus (taskbar improvements)
  Ctrl+Alt+Left / Right       previous / next workspace (Alt+1..4 also work)
  Ctrl+Alt+Shift+Left / Right  send the active window to the prev/next
                               workspace
  Alt+` / Alt+Shift+`          cycle windows - use these through noVNC
The focused window has a blue titlebar and a blue taskbar button; inactive
windows are muted grey. Click a taskbar button to focus/restore its window.
# <<< taskbar-switch-shortcuts <<<'
set_block "$SHORTCUTS" taskbar-switch-shortcuts "$shortcuts_block"
