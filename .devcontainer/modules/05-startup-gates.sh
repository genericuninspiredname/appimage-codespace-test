#!/usr/bin/env bash
# 05-startup-gates.sh - skip expensive setup work that already ran.
# perf/codespace-cost-controls: Codespaces bills compute per second of a
# RUNNING machine, and postStartCommand fires on every start. Work that is
# expensive (library overlays, hardlink trees, recursive chowns over possibly
# GB of app data) must not repeat on every start when nothing changed.
#
# Stamp files live in a directory that is wiped by a container REBUILD but
# survives a plain stop/start (anything outside /workspaces behaves this
# way in Codespaces). So:
#   - stop -> start:  stamps exist, expensive work is skipped
#   - rebuild:        stamps are gone, everything re-runs once
# The stamp records a hash of its inputs (source file + the upstream state
# it depends on, e.g. the flatpak commit id), so any change to the module
# or its inputs re-runs the work exactly once more.
#
# Override for tests with DESKTOP_STAMP_DIR.
STAMP_DIR="${DESKTOP_STAMP_DIR:-/var/lib/desktop-startup-stamps}"
mkdir -p "$STAMP_DIR"

# stamp_changed <name> <input>: succeeds when the work must (re)run.
stamp_changed() { # <name> <input>
  local stamp="$STAMP_DIR/$1"
  [ -f "$stamp" ] || return 0
  [ "$(cat "$stamp" 2>/dev/null)" = "$2" ] && return 1
  return 0
}

# stamp_done <name> <input>: mark the work as done for these inputs.
stamp_done() { # <name> <input>
  printf '%s' "$2" > "$STAMP_DIR/$1"
}

# mod_hash: md5 of the calling module's file. A gated section includes this
# in its stamp input, so editing the module re-runs its work exactly once.
mod_hash() {
  md5sum "${BASH_SOURCE[1]}" 2>/dev/null | cut -d' ' -f1
}
