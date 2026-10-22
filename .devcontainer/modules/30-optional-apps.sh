#!/usr/bin/env bash
# 30-optional-apps.sh - launchers and persistent data for the optional
# applications (opt-in via the OPTIONAL_APPS build arg; see README).
#
# This project runs entirely inside Codespaces, so optional apps are limited
# to ones that work there. The former Roblox (Sober) and Steam modules were
# removed: Roblox's anti-tamper blocks containers outright and Steam's client
# needs kernel namespaces Codespaces forbids - both would only ever work on
# an outside machine. PrismLauncher (Minecraft) support is retained as the
# remaining optional app.
#
# The desktop UI is unchanged whether or not the app is installed: the menu
# entry and this launcher always exist, and the launcher prints a
# "not installed" hint when the app files are absent (the image build
# installs them only when the token is set).
#
# Uses: HOMEDIR DATA_DIR BIN_DIR (and link_dir from 10-persistence.sh).
link_dir "$HOMEDIR/.local/share/PrismLauncher" "$DATA_DIR/private/prism"

cat > "$BIN_DIR/prismlauncher" <<'PL'
#!/bin/bash
# PrismLauncher (Minecraft) - launched from the desktop menu or a terminal.
if [ ! -x /opt/apps/prismlauncher/AppRun ]; then
  echo "PrismLauncher is not installed (run the container build/rebuild first)." >&2
  exit 1
fi
exec /opt/apps/prismlauncher/AppRun "$@"
PL
chmod +x "$BIN_DIR/prismlauncher"
