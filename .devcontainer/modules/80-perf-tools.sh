#!/usr/bin/env bash
# 80-perf-tools.sh - perf/codespace-cost-controls: small CPU/memory
# diagnostic + idle/inactivity check + cost-control helpers.
# Reinstalled on every setup run (same pattern as desktop-backup) so
# fixes reach existing codespaces; writing two small scripts is cheap.
# Uses: BIN_DIR.
mkdir -p "$BIN_DIR"

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
# terminal sessions have been idle and whether the usual desktop apps are
# running, then reminds you how to stop (free compute) or delete (also free
# storage) the codespace. Read-only: it never stops anything itself.
CS="${GITHUB_CODESPACE_NAME:-this codespace}"
echo "== Codespace idle check =="
echo "Codespace: $CS"
echo
echo "Terminal sessions (idle time):"
if w -h 2>/dev/null | grep -q .; then
  w -h | awk '{printf "  user %s on %s: idle %s\n", $1, $2, $5}'
else
  echo "  (no terminal sessions)"
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
echo "Done for now?  Stop the codespace (ends compute billing, keeps disk):"
echo "  gh codespace stop -c $CS"
echo "Done for good?  Delete it (also ends storage billing; ~/Files is lost"
echo "unless you ran Back Up Files first):"
echo "  gh codespace delete -c $CS"
echo
echo "See 'desktop-stats' for CPU/memory usage."
DI
chmod +x "$BIN_DIR/desktop-idle"
