#!/usr/bin/env bash
# 20-browser.sh - browser launcher + profile tuning.
# Split from setup.sh (cache flag, XWWW launcher, WebGL prefs); behavior unchanged.
# Uses: HOMEDIR.
# Codespaces blocks unshare/userns; skip the pkgforge AppImage namespaces
# check so Firefox (and other pkgforge apps) launch without a dialog.
mkdir -p "$HOMEDIR/.cache"
touch "$HOMEDIR/.cache/.disable-namespaces-check"

# Browser launcher: Firefox. Filters Chromium-specific flags it does not
# understand, and disables its content-process sandbox because Codespaces
# blocks the user namespaces it requires (Firefox shows a warning banner
# about this - expected in this environment).
XWWW="${DESKTOP_XWWW:-/usr/local/bin/x-www-browser}"
mkdir -p "$(dirname "$XWWW")"
cat > "$XWWW" <<'WB'
#!/bin/bash
flags=()
for a in "$@"; do
  case "$a" in
    --disable-dev-shm-usage|--disable-gpu|--no-sandbox) ;;
    *) flags+=("$a") ;;
  esac
done
exec env MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 \
  /opt/apps/firefox/AppRun "${flags[@]}"
WB
chmod +x "$XWWW"

# --- WebGL: the codespace has no GPU; Firefox renders WebGL in software
# (Mesa software rasterizer on the CPU). Force it on so blocklist entries
# for software renderers can not silently disable it. Written to every
# profile on each start; applied when Firefox next launches. ---
for prof in "$HOMEDIR"/.mozilla/firefox/*.default-release \
            "$HOMEDIR"/.mozilla/firefox/*.default; do
  [ -d "$prof" ] || continue
  # Managed prefs only: replace just our webgl lines, keep anything the
  # user authored in user.js.
  touch "$prof/user.js"
  # '|| true': grep -v exits 1 when it filters out every line (normal here).
  { grep -vF 'user_pref("webgl.force-enabled"' "$prof/user.js" \
      | grep -vF 'user_pref("webgl.disabled"'; } > "$prof/user.js.new" || true
  printf 'user_pref("webgl.force-enabled", true);\nuser_pref("webgl.disabled", false);\n' \
    >> "$prof/user.js.new"
  mv "$prof/user.js.new" "$prof/user.js"
done
