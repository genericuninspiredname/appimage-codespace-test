#!/usr/bin/env bash
# Codespace verification for ui/taskbar-and-window-switching.
# Run INSIDE the codespace (gh codespace ssh -c taskbar-test -- bash /workspaces/appimage-codespace-test/tests/codespace-verify.sh)
# Verifies: config files, noVNC serving, several windows open, key bindings
# via X key injection (the same X input path noVNC uses), workspace switching,
# taskbar/menu intact, idempotent repeat run, fluxbox restart survival.
set -u
FLUX="$HOME/.fluxbox"
REPO=/workspaces/appimage-codespace-test
PASS=0; FAIL=0
ok()   { echo "PASS: $*"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $*"; FAIL=$((FAIL+1)); }
chk()  { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
export DISPLAY=${DISPLAY:-:1}

echo "== 1. fluxbox config =="
[ -d "$FLUX" ] && ok "~/.fluxbox exists" || bad "~/.fluxbox missing"
chk "managed overlay block once"      "[ \"\$(grep -c '^# >>> taskbar-switch-overlay >>>' $FLUX/overlay)\" = 1 ]"
chk "managed keys block once"         "[ \"\$(grep -c '^# >>> taskbar-switch-keys >>>' $FLUX/keys)\" = 1 ]"
chk "base overlay block still once"   "[ \"\$(grep -c '^# >>> desktop-overlay >>>' $FLUX/overlay)\" = 1 ]"
chk "menu managed block still once"  "[ \"\$(grep -c '^# >>> desktop-apps >>>' $FLUX/menu)\" = 1 ]"
chk "taskbar font set"                "grep -qx '\*.font: sans-10' $FLUX/overlay"
chk "focused titlebar accent"         "grep -q 'window.title.focus.color: rgb:3A/5C/8E' $FLUX/overlay"
chk "unfocused titlebar muted"        "grep -q 'window.title.unfocus.color: rgb:1F/1F/2C' $FLUX/overlay"
chk "Ctrl+Alt+Left workspace key"     "grep -qx 'Control Mod1 Left :PrevWorkspace' $FLUX/keys"
chk "Ctrl+Alt+Shift+Left send key"   "grep -qx 'Control Mod1 Shift Left :SendToPrevWorkspace' $FLUX/keys"
chk "menu entries preserved"          "grep -q '\[exec\] (Run Program...)' $FLUX/menu"
chk "shortcuts sheet updated"         "grep -q 'taskbar-switch-shortcuts' $FLUX/SHORTCUTS"

echo "== 2. noVNC serving =="
curl -sf -o /dev/null http://localhost:6080/ && ok "noVNC http on 6080" || bad "noVNC http on 6080"
pgrep -x fluxbox >/dev/null && ok "fluxbox running" || bad "fluxbox not running"
pgrep -x Xvnc >/dev/null && ok "Xvnc running" || bad "Xvnc not running"

echo "== 3. open several windows =="
command -v xdotool >/dev/null || { echo "xdotool not installed"; exit 1; }
mousepad /etc/hostname >/dev/null 2>&1 &
sleep 1
tilix >/dev/null 2>&1 &
sleep 2
DISPLAY=$DISPLAY xdg-open / >/dev/null 2>&1 || nautilus / >/dev/null 2>&1 &
sleep 3
N=$(xdotool search --onlyvisible --name '' 2>/dev/null | wc -l)
chk "several windows open ($N)" "[ \"$N\" -ge 3 ]"

echo "== 4. active/inactive window state =="
ACTIVE=$(xdotool getactivewindow getwindowname 2>/dev/null)
echo "  active window: $ACTIVE"
chk "an active window exists" "[ -n \"\$ACTIVE\" ]"

echo "== 5. window cycling via Alt+grave (noVNC-safe) =="
W1=$(xdotool getactivewindow)
xdotool key alt+grave; sleep 0.5
W2=$(xdotool getactivewindow)
chk "Alt+grave cycles focus" "[ \"\$W1\" != \"\$W2\" ]"
xdotool key alt+shift+grave; sleep 0.5
W3=$(xdotool getactivewindow)
chk "Alt+Shift+grave cycles back" "[ \"\$W1\" = \"\$W3\" ]"

echo "== 6. workspace switching via Ctrl+Alt+Right/Left =="
ws() { xprop -root _NET_CURRENT_DESKTOP 2>/dev/null | awk '{print $3}'; }
X1=$(ws)
xdotool key ctrl+alt+Right; sleep 0.7
X2=$(ws)
chk "Ctrl+Alt+Right switches workspace ($X1 -> $X2)" "[ \"\$X1\" != \"\$X2\" ]"
xdotool key ctrl+alt+Left; sleep 0.7
X3=$(ws)
chk "Ctrl+Alt+Left returns ($X2 -> $X3)" "[ \"\$X1\" = \"\$X3\" ]"

echo "== 7. send window to next workspace via Ctrl+Alt+Shift+Right =="
AW=$(xdotool getactivewindow)
xdotool key ctrl+alt+shift+Right; sleep 0.7
# window should now be on the next workspace (not this one)
FOUND=$(xdotool search --all --onlyvisible --name '' 2>/dev/null | grep -c "^$AW$" || true)
chk "window left current workspace" "[ \"\$FOUND\" = 0 ]"
xdotool key ctrl+alt+Right; sleep 0.7
FOUND2=$(xdotool search --onlyvisible --name '' 2>/dev/null | grep -c "^$AW$" || true)
chk "window present on next workspace" "[ \"\$FOUND2\" = 1 ]"

echo "== 8. desktop menu intact =="
chk "root menu bound" "grep -q 'OnDesktop Mouse3 :RootMenu' $FLUX/keys"

echo "== 9. repeat-run idempotence (normal-start) =="
md5sum $FLUX/init $FLUX/keys $FLUX/overlay $FLUX/menu $FLUX/SHORTCUTS > /tmp/taskbar-md5-before.txt
bash $REPO/.devcontainer/setup.sh normal-start >/tmp/taskbar-setup2.log 2>&1
chk "repeat setup exits 0" "[ $? -eq 0 ]"
md5sum $FLUX/init $FLUX/keys $FLUX/overlay $FLUX/menu $FLUX/SHORTCUTS > /tmp/taskbar-md5-after.txt
chk "config byte-identical after repeat run" "diff -q /tmp/taskbar-md5-before.txt /tmp/taskbar-md5-after.txt >/dev/null"

echo "== 10. fluxbox restart keeps windows =="
BEFORE=$(xdotool search --onlyvisible --name '' 2>/dev/null | wc -l)
fluxbox-remote restart >/dev/null 2>&1 || DISPLAY=$DISPLAY fluxbox-remote restart >/dev/null 2>&1
sleep 2
AFTER=$(xdotool search --onlyvisible --name '' 2>/dev/null | wc -l)
chk "windows survive restart ($BEFORE -> $AFTER)" "[ \"$AFTER\" -ge \"$BEFORE\" ]"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
