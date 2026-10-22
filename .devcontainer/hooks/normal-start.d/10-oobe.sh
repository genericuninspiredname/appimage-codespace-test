#!/usr/bin/env bash
# 10-oobe.sh - first-run welcome screen (normal-start hook).
#
# desktop-welcome --auto is a one-shot: it checks the persistent
# $DATA_DIR/.oobe-shown marker (nothing happens once onboarding ran),
# waits (bounded) for the desktop display, shows the dialog once and
# exits. No background service keeps running afterwards. Launched
# detached so setup is never blocked by the display wait; a failed
# launch writes no marker and is retried on the next start.
[ -x "${BIN_DIR:-/usr/local/bin}/desktop-welcome" ] || exit 0
# DESKTOP_WELCOME_LOG (test isolation) defaults to the shared runtime log.
setsid "${BIN_DIR:-/usr/local/bin}/desktop-welcome" --auto \
  </dev/null >"${DESKTOP_WELCOME_LOG:-/tmp/desktop-welcome.log}" 2>&1 &
exit 0
