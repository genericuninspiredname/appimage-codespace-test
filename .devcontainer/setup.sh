#!/usr/bin/env bash
# Idempotent setup: persistent file system + app settings + backup tool.
# Runs on codespace creation (postCreate) and every start (postStart).
#
# This file is only the COORDINATOR. All real work lives in modules/*.sh,
# sourced in lexical order; feature branches should add a new module or a
# hook script instead of editing existing files (see hooks/README.md).
set -e

HOMEDIR="${DESKTOP_HOME:-$HOME}"
DATA_DIR="${DESKTOP_DATA_DIR:-/workspaces/desktop-data}"
BIN_DIR="${DESKTOP_BIN_DIR:-/usr/local/bin}"
REPO_DIR="${DESKTOP_REPO_DIR:-}"
if [ -z "$REPO_DIR" ]; then
  REPO_DIR=$(dirname "$(find /workspaces -maxdepth 2 -name .git -type d 2>/dev/null | head -1)")
  [ -d "$REPO_DIR" ] || REPO_DIR=/workspaces/appimage-codespace-test
fi
REMOTE_URL="${DESKTOP_REMOTE_URL:-$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo https://github.com/genericuninspiredname/appimage-codespace-test.git)}"

DEVCONTAINER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export HOMEDIR DATA_DIR BIN_DIR REPO_DIR REMOTE_URL
_setup_t0=$(date +%s%N)
_mod_times=""

# ---------------------------------------------------------------------------
# Lifecycle mode. Codespaces calls this script with an explicit mode:
#   postCreateCommand -> first-start   (runs once per codespace)
#   postStartCommand  -> normal-start  (runs on every start/rebuild)
# Without an argument, the persisted marker decides: a data dir that has
# completed a first start is in normal-start territory.
# ---------------------------------------------------------------------------
MODE="${1:-}"
if [ -z "$MODE" ]; then
  if [ -f "$DATA_DIR/.first-start-complete" ]; then MODE=normal-start; else MODE=first-start; fi
fi
case "$MODE" in
  first-start|normal-start) ;;
  *) echo "Usage: $0 [first-start|normal-start]" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Modules. Sourced (not executed) so they share this shell's environment
# and the "set -e" above; a failing module aborts the run, exactly as a
# failing section did in the monolithic setup.sh.
# ---------------------------------------------------------------------------
for module in "$DEVCONTAINER_DIR"/modules/[0-9]*.sh; do
  # shellcheck source=/dev/null
  _t0=$(date +%s%N)
  . "$module"
  _t1=$(date +%s%N)
  _mod_times+="$(basename "$module")=$(( (_t1 - _t0) / 1000000 ))ms "
done
# Startup timing (perf/codespace-cost-controls): makes it visible which
# modules dominate a start, so regressions are caught early. Cheap (two
# date calls per module) and runs in both modes.
echo "Setup timing: mode=$MODE modules=$(( ($(date +%s%N) - _setup_t0) / 1000000 ))ms (${_mod_times:-none}; hooks excluded)"

# ---------------------------------------------------------------------------
# Lifecycle hooks. Stable extension points for feature branches:
#   hooks/first-start.d/*.sh  - once per codespace lifetime (creation)
#   hooks/normal-start.d/*.sh - on every start, including after a rebuild
# Hooks run in lexical order after all modules. A failing hook is reported
# loudly but does not abort the rest of the setup: a broken optional
# feature must not take down the whole desktop.
#
# postCreateCommand also fires on a container rebuild, so an explicit
# first-start is still gated on the persisted marker: first-start hooks
# run only once per codespace unless they failed (no marker is written
# until every first-start hook has succeeded, so the next run retries).
# ---------------------------------------------------------------------------
hook_failures=0
run_hooks() { # run_hooks <dir>
  local hook
  for hook in "$1"/*.sh; do
    [ -f "$hook" ] || continue
    if ! bash "$hook"; then
      echo "WARNING: hook failed: $hook" >&2
      hook_failures=$((hook_failures + 1))
    fi
  done
}
if [ "$MODE" = first-start ]; then
  if [ -f "$DATA_DIR/.first-start-complete" ]; then
    echo "First start already complete - skipping first-start hooks."
  else
    run_hooks "$DEVCONTAINER_DIR/hooks/first-start.d"
    # Record completion only when every first-start hook succeeded, so a
    # failed hook is retried on the next run.
    if [ "$hook_failures" -eq 0 ]; then
      mkdir -p "$DATA_DIR"
      touch "$DATA_DIR/.first-start-complete"
    fi
  fi
else
  run_hooks "$DEVCONTAINER_DIR/hooks/normal-start.d"
fi

if [ "$hook_failures" -gt 0 ]; then
  echo "Setup finished with $hook_failures hook failure(s) - see warnings above." >&2
else
  echo "Setup complete - open the forwarded port 6080 in your browser."
fi
