#!/usr/bin/env bash
# 50-menu.sh - Fluxbox desktop menu entries.
# Split from setup.sh (section 4); behavior unchanged.
# Uses: HOMEDIR.
# ---------------------------------------------------------------------------
# 4. Desktop menu entries (managed block: replaced wholesale on every run,
#    so upgrades add entries without duplicating old ones)
# ---------------------------------------------------------------------------
MENU="$HOMEDIR/.fluxbox/menu"

if [ -f "$MENU" ]; then
  awk -v home="$HOMEDIR" -v fluxdir="$HOMEDIR/.fluxbox" '
    BEGIN {
      block = "# >>> desktop-apps >>>\n[exec] (Prism Launcher) {prismlauncher}\n[exec] (Run Program...) {fbrun}\n[exec] (Task Manager) {tilix -e htop}\n[exec] (System Stats) {tilix -e desktop-stats}\n[exec] (Idle Check) {tilix -e desktop-idle}\n[exec] (Files) {nautilus " home "/Files}\n[exec] (Keyboard Shortcuts) {mousepad " fluxdir "/SHORTCUTS}\n[submenu] (Encrypted Profiles) {}\n[exec] (Save Profile) {tilix -t \"Save Profile\" -e desktop-profile save}\n[exec] (Restore Profile) {tilix -t \"Restore Profile\" -e desktop-profile restore}\n[exec] (List Profiles) {tilix -t \"Profiles\" -e desktop-profile list}\n[end]\n[exec] (Back Up Files) {tilix -e desktop-backup}\n[restart] (Apply Desktop Updates) {}\n# <<< desktop-apps <<<"
      inblock = 0
    }
    /^# >>> desktop-apps >>>/ { inblock = 1; next }
    /^# <<< desktop-apps <<</ { inblock = 0; next }
    inblock { next }
    # drop entries written by older versions of this script
    /\[exec\] \(Helium Browser\)/ { next }
    /\[exec\] \(OBS Studio\)/ { next }
    /\[exec\] \(Start Audio\)/ { next }
    /\[exec\] \(Volume Control\)/ { next }
    !done && /\[begin\]/ { print; print block; done = 1; next }
    { print }
  ' "$MENU" > "$MENU.new" && mv "$MENU.new" "$MENU"
fi
