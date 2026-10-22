#!/usr/bin/env bash
# 80-perf-tools.sh - perf/codespace-cost-controls: small CPU/memory
# diagnostic + idle/inactivity check + cost-control helpers.
# Reinstalled on every setup run (same pattern as desktop-backup) so
# fixes reach existing codespaces; writing two small scripts is cheap.
# Uses: BIN_DIR.
mkdir -p "$BIN_DIR"

# xprintidle (real desktop-input idle for desktop-idle) is installed on
# demand - once per image, guarded so hermetic test runs (which set
# DESKTOP_STAMP_DIR) and non-root contexts skip it, and a failed install
# never breaks setup (desktop-idle degrades gracefully without it).
if [ -z "${DESKTOP_STAMP_DIR:-}" ] && [ "$(id -u)" = 0 ] \
   && ! command -v xprintidle >/dev/null 2>&1; then
  apt-get update -q >/dev/null 2>&1 || true
  apt-get install -y -q --no-install-recommends xprintidle >/dev/null 2>&1 || true
fi

# --- desktop-stats: quick CPU + memory snapshot of the codespace. ---------
cat > "$BIN_DIR/desktop-stats" <<'DS'
#!/usr/bin/env bash
# CPU + memory diagnostic for the codespace desktop (perf controls).
# Deliberately small: reads /proc and ps once, no monitoring loop.
echo "== Codespace desktop stats =="
echo "Date:    $(date)"
echo "Uptime:  $(uptime -p 2>/dev/null || uptime)"
echo "CPUs:    $(nproc)   Load (1/5/15 min): $(cut -d' ' -f1-3 /proc/loadavg)"
echo
free -m | awk '
  /^Mem:/  {printf "Memory:  %s MB total, %s MB used, %s MB available\n", $2, $3, $7}
  /^Swap:/ {printf "Swap:    %s MB total, %s MB used\n", $2, $3}'
echo
echo "Top processes by memory:"
ps -eo pcpu,pmem,rss,comm --sort=-rss | head -6 | awk '
  NR==1 {printf "%-7s %-6s %-8s %s\n","%CPU","%MEM","RSS(KB)","COMMAND"; next}
  {printf "%-7s %-6s %-8s %s\n", $1, $2, $3, $4}'
DS
chmod +x "$BIN_DIR/desktop-stats"

# --- desktop-idle: inactivity check + stop/delete reminders. ---------------
cat > "$BIN_DIR/desktop-idle" <<'DI'
#!/usr/bin/env bash
# Idle/inactivity check for the codespace (perf controls). Reports how long
# terminal sessions and the DESKTOP (X server input) have been idle, then
# reminds you how to stop (free compute) or delete (also free storage) the
# codespace. Read-only: it never stops anything itself.
CS="${CODESPACE_NAME:-${GITHUB_CODESPACE_NAME:-}}"
echo "== Codespace idle check =="
if [ -n "$CS" ]; then
  echo "Codespace: $CS"
else
  echo "Codespace: (name not set in this shell - run 'gh codespace list' to see it)"
fi
echo
echo "Desktop input idle (time since last mouse/keyboard on the desktop):"
if command -v xprintidle >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  ms=$(xprintidle 2>/dev/null)
  if [ -n "$ms" ]; then
    awk -v ms="$ms" 'BEGIN {
      m = int(ms / 60000)
      if (m < 1)       print "  active (last input less than a minute ago)"
      else if (m < 60) printf "  idle for %d minute(s)\n", m
      else             printf "  idle for %d hour(s) %d minute(s)\n", int(m/60), m%60
    }'
  else
    echo "  unknown (xprintidle could not reach the display)"
  fi
else
  echo "  unknown (xprintidle not available, or DISPLAY not set -"
  echo "  run this from the desktop terminal or set DISPLAY=:1)"
fi
echo
echo "Terminal sessions (idle time):"
if w -h 2>/dev/null | grep -q .; then
  w -h | awk '{printf "  user %s on %s: idle %s\n", $1, $2, $5}'
else
  echo "  (no registered terminal sessions - SSH sessions may not register)"
fi
echo
echo "Desktop apps currently running:"
found=0
for p in fluxbox Xvnc websockify firefox steam prismlauncher; do
  if pgrep -x "$p" >/dev/null 2>&1; then
    echo "  $p (pid $(pgrep -x "$p" | head -1))"
    found=1
  fi
done
[ "$found" = 0 ] && echo "  (none - only the bare desktop, if that)"
echo
echo "Idle timeout: Codespaces stops the machine automatically after your"
echo "idle timeout (default 30 min; change it at github.com/settings/codespaces)."
echo
if [ -n "$CS" ]; then
  echo "Done for now?  Stop the codespace (ends compute billing, keeps disk):"
  echo "  gh codespace stop -c $CS"
  echo "Done for good?  Delete it (also ends storage billing; ~/Files is lost"
  echo "unless you ran Back Up Files first):"
  echo "  gh codespace delete -c $CS"
else
  echo "Done for now?  Stop the codespace (ends compute billing, keeps disk):"
  echo "  gh codespace stop   (add '-c <name>' from 'gh codespace list')"
  echo "Done for good?  Delete it (also ends storage billing; back up first):"
  echo "  gh codespace delete (add '-c <name>' from 'gh codespace list')"
fi
echo
echo "See 'desktop-stats' for CPU/memory usage."
DI
chmod +x "$BIN_DIR/desktop-idle"
