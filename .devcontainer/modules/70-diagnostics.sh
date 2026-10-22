#!/usr/bin/env bash
# 70-diagnostics.sh - environment health: git safe.directory, reapply to a
# running desktop. Split from setup.sh; behavior unchanged apart from the
# safe.directory entries now being added only once (idempotent repeats).
# Codespaces' clone can be owned by a different uid after rebuilds; stop
# git's dubious-ownership check from breaking pulls on the working dir.
# Added only when absent so repeated runs do not append duplicates.
add_safe_directory() { # <path>
  git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$1" \
    || git config --global --add safe.directory "$1" 2>/dev/null || true
}
add_safe_directory "$REPO_DIR"
add_safe_directory /workspaces/appimage-codespace-test

# --- apply to a running desktop: this script can run after the desktop has
# already started (postStart). Restarting fluxbox re-reads init/keys/menu/
# overlay, keeps every window open, and takes under a second. ---
if pgrep -x fluxbox >/dev/null 2>&1; then
  DISPLAY="${DISPLAY:-:1}" fluxbox-remote restart >/dev/null 2>&1 || true
fi
