#!/usr/bin/env bash
# 72-webgl-diagnostics.sh - install the `desktop-doctor` diagnostics tool:
# WebGL availability + software/hardware rendering, desktop resolution and
# color depth, CPU and memory usage, with troubleshooting hints. Terminal
# first (`desktop-doctor` in any terminal); also reachable from the
# Fluxbox menu via its own managed block, so 50-menu.sh stays untouched.
# Uses: HOMEDIR BIN_DIR.
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/desktop-doctor" <<'DOCTOR'
#!/usr/bin/env bash
# desktop-doctor - lightweight diagnostics for the codespace desktop.
#
#   WebGL      : context-creation probe in the app's browser (on the
#                desktop display when one is reachable, else headless),
#                plus Firefox WebGL prefs and GLX evidence
#   Rendering  : renderer string -> software / hardware / unknown
#                (masked renderer strings stay unknown)
#   Display    : current desktop resolution and color depth (virtual
#                VNC display identified as such)
#   CPU        : usage sampled over 1s, core count, container CPU quota,
#                load average (scopes labeled; host != container limits)
#   Memory     : container usage vs limit, host totals, swap
#
# Usage: desktop-doctor [--help] [--no-probe]
#   --no-probe  skip the browser probe; report prefs + GLX evidence only
#
# Exit codes: 0 = all checks ran, none failed (warnings allowed)
#             1 = at least one check failed or could not run
#             2 = bad command-line option
#
# Pure helpers (classify_renderer, parse_cgroup_cpu, parse_cgroup_mem,
# parse_xdpy) are functions so tests/diagnostics-test.sh can source this
# file and exercise them, and probe_webgl can be driven end-to-end with
# a stub browser (DESKTOP_FIREFOX + DESKTOP_DOCTOR_PROBE_TIMEOUT).
set -u

# probe timeout (overridable for tests); browser path is resolved per call
PROBE_TIMEOUT="${DESKTOP_DOCTOR_PROBE_TIMEOUT:-60}"  # seconds for the probe

# --- output helpers (plain when not a tty) -----------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  C_OK=$(tput setaf 2)   C_WARN=$(tput setaf 3)   C_BAD=$(tput setaf 1)
  C_DIM=$(tput setaf 7)  C_HEAD=$(tput bold)      C_OFF=$(tput sgr0)
else
  C_OK="" C_WARN="" C_BAD="" C_DIM="" C_HEAD="" C_OFF=""
fi
PASS=0 WARNED=0 FAILED=0
HINTS=()
section() { printf '\n%s== %s ==%s\n' "$C_HEAD" "$*" "$C_OFF"; }
ok()    { PASS=$((PASS+1));   printf '  %s[ ok ]%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn()  { WARNED=$((WARNED+1)); printf '  %s[warn]%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
bad()   { FAILED=$((FAILED+1)); printf '  %s[FAIL]%s %s\n' "$C_BAD" "$C_OFF" "$*"; }
note()  { printf '         %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
hint()  { HINTS+=("$*"); }

# --- pure helpers (no side effects; unit-tested) ------------------------------
# classify_renderer <string> -> software | hardware | unknown
# A renderer string only counts as evidence when it names a real
# implementation; generic/masked strings (no WEBGL_debug_renderer_info)
# stay unknown rather than being assumed hardware.
classify_renderer() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    ""|"unknown"|"mozilla"*|"webkit webgl"*|*"webgl is disabled"*) echo "unknown" ;;
    *llvmpipe*|*softpipe*|*swrast*|*software*|*swiftshader*|*basic\ render*|*mesa\ offscreen*|*angle\ \(software*) echo "software" ;;
    *) echo "hardware" ;;
  esac
}

# parse_cgroup_cpu <dir> -> "<cores>" | "none" | "unknown"  (v2 then v1)
parse_cgroup_cpu() {
  if [ -r "$1/cpu.max" ]; then
    read -r quota period < "$1/cpu.max"
    [ "$quota" = "max" ] && { echo "none"; return; }
    awk -v q="$quota" -v p="$period" 'BEGIN{if (p>0) {printf "%.2f", q/p; exit} exit 1}' \
      && return
    echo "unknown"; return
  fi
  if [ -r "$1/cpu/cpu.cfs_quota_us" ] && [ -r "$1/cpu/cpu.cfs_period_us" ]; then
    q=$(cat "$1/cpu/cpu.cfs_quota_us"); p=$(cat "$1/cpu/cpu.cfs_period_us")
    [ "$q" -le 0 ] 2>/dev/null && { echo "none"; return; }
    awk -v q="$q" -v p="$p" 'BEGIN{if (p>0) {printf "%.2f", q/p; exit} exit 1}' \
      && return
    echo "unknown"; return
  fi
  echo "unknown"
}

# parse_cgroup_mem <dir> -> "<cur_bytes> <max_bytes|0>"  (0 = no limit)
#                                       (v2; empty when no controller)
parse_cgroup_mem() {
  if [ -r "$1/memory.current" ]; then
    cur=$(cat "$1/memory.current"); max=$(cat "$1/memory.max" 2>/dev/null || echo max)
    [ "$max" = "max" ] && max=0
    echo "$cur $max"
  elif [ -r "$1/memory/memory.limit_in_bytes" ]; then
    cur=$(cat "$1/memory/memory.usage_in_bytes" 2>/dev/null || echo 0)
    max=$(cat "$1/memory/memory.limit_in_bytes" 2>/dev/null || echo 0)
    [ "$max" -ge 9223372036854771712 ] 2>/dev/null && max=0
    echo "$cur $max"
  fi
}

# parse_xdpy <xdpyinfo-output> -> "<WxH> <depth>"  (empty when unusable)
parse_xdpy() {
  local dims depth
  dims=$(printf '%s\n' "$1" | awk '/dimensions:/{print $2; exit}')
  depth=$(printf '%s\n' "$1" | awk '/depth of root window:/{print $5; exit}')
  [ -n "$dims" ] && [ -n "$depth" ] && echo "$dims $depth"
}

# --- display discovery ---------------------------------------------------------
find_display() {
  if [ -n "${DISPLAY:-}" ]; then echo "$DISPLAY"; return 0; fi
  local d
  for d in :1 :0; do
    command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo -display "$d" >/dev/null 2>&1 \
      && { echo "$d"; return 0; }
  done
  return 1
}

# --- browser WebGL probe -------------------------------------------------------
# Serves the probe page from a local one-shot server, launches the app's
# browser against it (on the desktop display when one is reachable - the
# same rendering path as a normal session, a window may flash briefly;
# headless otherwise), and records the page's own report: which context
# type it could create and the unmasked renderer string. The browser
# runs with its normal configuration - nothing is disabled to make the
# probe pass. rc: 0 = result received, 1 = could not launch,
# 2 = launched but no result (page or browser never delivered).
probe_webgl() { # -> sets PROBE_* and PROBE_MODE
  local work port collector ff i line firefox_bin
  firefox_bin="${DESKTOP_FIREFOX:-/opt/apps/firefox/AppRun}"
  command -v python3 >/dev/null 2>&1 || { hint "python3 not found - browser probe skipped."; return 1; }
  [ -x "$firefox_bin" ] || { hint "Browser not found at $firefox_bin - set DESKTOP_FIREFOX to override."; return 1; }
  work=$(mktemp -d /tmp/desktop-doctor.XXXXXX) || return 1
  mkdir -p "$work/profile"

  port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()') \
    || { rm -rf "$work"; return 1; }

  # probe page: webgl2 -> webgl -> experimental-webgl, then report home
  # to the same server that served the page (same origin, no CORS)
  cat > "$work/page.html" <<PAGE
<!doctype html><html><body><script>
function probe(){
  var o={};
  try{
    var c=document.createElement('canvas');
    var g2=c.getContext('webgl2');
    var g=g2||c.getContext('webgl')||c.getContext('experimental-webgl');
    o.ctx=g2?'webgl2':(g?'webgl':'none');
    if(g){
      var d=g.getExtension('WEBGL_debug_renderer_info');
      o.masked=!d;
      o.renderer=d?g.getParameter(d.UNMASKED_RENDERER_WEBGL):g.getParameter(g.RENDERER);
      o.vendor=d?g.getParameter(d.UNMASKED_VENDOR_WEBGL):g.getParameter(g.VENDOR);
    }
  }catch(e){o.error=''+e}
  return o;
}
new Image().src='/r?d='+encodeURIComponent(JSON.stringify(probe()));
setTimeout(function(){try{window.close();}catch(e){}},500);
</script></body></html>
PAGE

  # collector: serves the page, records the page fetch, records the
  # result, lives as long as the whole probe window
  cat > "$work/collect.py" <<PY
import http.server, sys, threading, urllib.parse
out, port, page, life = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
page = open(page, 'rb').read()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        p = urllib.parse.urlparse(self.path)
        if p.path == '/page':
            open(out + '.page', 'a').close()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(page)
        elif p.path == '/r':
            d = urllib.parse.parse_qs(p.query).get('d', [''])[0]
            with open(out, 'w') as f: f.write(d)
            self.send_response(204); self.end_headers()
            threading.Thread(target=self.server.shutdown, daemon=True).start()
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', port), H)
t = threading.Thread(target=srv.serve_forever, daemon=True); t.start()
t.join(life)
PY

  python3 "$work/collect.py" "$work/result.json" "$port" "$work/page.html" \
    "$((PROBE_TIMEOUT + 15))" &
  collector=$!
  # wait for the collector to accept connections
  for i in $(seq 1 40); do
    (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && { exec 3>&-; break; }
    sleep 0.25
  done

  PROBE_MODE="headless"
  PROBE_URL="http://127.0.0.1:$port/page"
  if [ -n "${DISPLAY_FOUND:-}" ]; then
    PROBE_MODE="desktop display $DISPLAY_FOUND"
    DISPLAY="$DISPLAY_FOUND" timeout -k 5 "$PROBE_TIMEOUT" "$firefox_bin" \
      --profile "$work/profile" --new-instance "$PROBE_URL" \
      > "$work/ff.log" 2>&1 &
  else
    MOZ_HEADLESS=1 timeout -k 5 "$PROBE_TIMEOUT" "$firefox_bin" \
      --profile "$work/profile" --new-instance "$PROBE_URL" \
      > "$work/ff.log" 2>&1 &
  fi
  ff=$!

  # give the browser a moment; note an immediate exit for the report
  sleep 3
  PROBE_EARLY_EXIT=0
  kill -0 "$ff" 2>/dev/null || {
    PROBE_EARLY_EXIT=1
    PROBE_STDERR=$(grep -m2 . "$work/ff.log" 2>/dev/null | tr '\n' ' ' | cut -c1-160)
  }

  for i in $(seq 1 $((PROBE_TIMEOUT + 2))); do
    [ -s "$work/result.json" ] && break
    sleep 1
  done
  kill "$ff" "$collector" 2>/dev/null; wait "$ff" "$collector" 2>/dev/null

  if [ -s "$work/result.json" ]; then
    PROBE_CTX=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("ctx",""))' "$work/result.json" 2>/dev/null)
    PROBE_RENDERER=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("renderer",""))' "$work/result.json" 2>/dev/null)
    PROBE_VENDOR=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("vendor",""))' "$work/result.json" 2>/dev/null)
    PROBE_MASKED=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("masked",""))' "$work/result.json" 2>/dev/null)
    rm -rf "$work"
    return 0
  fi
  PROBE_PAGE_FETCHED=0
  [ -e "$work/result.json.page" ] && PROBE_PAGE_FETCHED=1
  rm -rf "$work"
  return 2
}

# --- sections -------------------------------------------------------------------
check_webgl() {
  local local_prefs glx glx_renderer rc
  PROBE_CTX="" PROBE_RENDERER="" PROBE_VENDOR="" PROBE_MASKED=""
  PROBE_PAGE_FETCHED=0 PROBE_EARLY_EXIT=0 PROBE_STDERR=""

  if [ "${1:-}" != "--no-probe" ]; then
    probe_webgl; rc=$?
    if [ "$rc" -eq 0 ]; then
      case "$PROBE_CTX" in
        webgl2|webgl)
          WEBGL_STATUS="available"
          ok "WebGL context created in Firefox ($PROBE_MODE probe): $PROBE_CTX"
          note "renderer: ${PROBE_RENDERER:-<not reported>}"
          [ -n "$PROBE_VENDOR" ] && note "vendor: $PROBE_VENDOR"
          ;;
        none)
          WEBGL_STATUS="unavailable"
          bad "WebGL context creation failed in Firefox ($PROBE_MODE probe)"
          hint "WebGL probe reported no context: check the Firefox prefs below and restart the browser."
          ;;
        *)
          WEBGL_STATUS="unknown"
          bad "Browser probe returned no usable result"
          ;;
      esac
    else
      WEBGL_STATUS="unknown"
      if [ "$rc" -eq 2 ]; then
        bad "WebGL check could not run - no probe result received (${PROBE_MODE}, timeout ${PROBE_TIMEOUT}s)"
        if [ "$PROBE_EARLY_EXIT" = "1" ]; then
          note "The browser exited immediately. stderr: ${PROBE_STDERR:-<none>}"
          hint "Browser exited immediately when probed: it may be missing libraries - try launching it from the desktop once."
        elif [ "$PROBE_PAGE_FETCHED" = "1" ]; then
          note "The probe page loaded in the browser, but no result came back within ${PROBE_TIMEOUT}s."
          hint "Page loaded but no WebGL result: the page's script may be blocked - check about:config for javascript.enabled."
        else
          note "The browser never loaded the probe page (timeout ${PROBE_TIMEOUT}s; first launch can be slow)."
          hint "Browser did not load the probe page: if the desktop browser also fails to open pages, the problem is general browser rendering, not WebGL-specific."
        fi
      else
        bad "WebGL check could not run - the browser could not be launched"
        note "Falling back to Firefox prefs + GLX evidence below."
        hint "WebGL probe could not run: verify the browser is installed."
      fi
    fi
  else
    note "Browser probe skipped (--no-probe)."
  fi

  if [ "$WEBGL_STATUS" = "available" ]; then
    if [ "$PROBE_MASKED" = "True" ] || [ "$PROBE_MASKED" = "true" ] || [ -z "$PROBE_RENDERER" ]; then
      RENDER_TYPE="unknown"   # masked/generic renderer info is not evidence
    else
      RENDER_TYPE=$(classify_renderer "$PROBE_RENDERER")
    fi
  elif [ "$WEBGL_STATUS" = "unavailable" ]; then
    RENDER_TYPE="unknown"
  fi

  # managed Firefox WebGL prefs (every profile)
  if ls "$HOME"/.mozilla/firefox/*.default*/user.js >/dev/null 2>&1; then
    local_prefs=$(grep -h 'webgl\.\(disabled\|force-enabled\)' \
      "$HOME"/.mozilla/firefox/*.default*/user.js 2>/dev/null | sort -u)
    if [ -n "$local_prefs" ]; then
      while IFS= read -r line; do note "pref: $line"; done <<< "$local_prefs"
      grep -q 'user_pref("webgl.disabled", true)' <<< "$local_prefs" \
        && { warn "webgl.disabled is true in a Firefox profile"
             hint "webgl.disabled=true found: remove it (setup normally forces WebGL on)."; }
    else
      note "no webgl prefs found in Firefox profiles"
    fi
  else
    note "no Firefox profiles with managed webgl prefs found in ~/.mozilla"
  fi

  # GLX evidence on the desktop display
  DISPLAY_FOUND=$(find_display)
  if [ -n "$DISPLAY_FOUND" ] && command -v glxinfo >/dev/null 2>&1; then
    glx=$(DISPLAY="$DISPLAY_FOUND" glxinfo -B 2>/dev/null)
    glx_renderer=$(awk -F': *' '/OpenGL renderer string/{print $2; exit}' <<< "$glx")
    if [ -n "$glx_renderer" ]; then
      note "GLX renderer on display $DISPLAY_FOUND: $glx_renderer"
      if [ "$RENDER_TYPE" = "unknown" ] && [ "$WEBGL_STATUS" != "available" ] \
         && [ -n "$glx_renderer" ]; then
        RENDER_TYPE=$(classify_renderer "$glx_renderer")
        [ "$RENDER_TYPE" != "unknown" ] \
          && note "(GLX evidence only - browser context not verified)"
      fi
    fi
  elif [ -n "$DISPLAY_FOUND" ]; then
    note "glxinfo not installed - GLX evidence unavailable (apt-get install mesa-utils)"
  fi

  case "$RENDER_TYPE" in
    software)
      warn "Rendering: SOFTWARE (${PROBE_RENDERER:-${glx_renderer:-}})"
      note "expected in a codespace - there is no GPU; Mesa (llvmpipe) renders on the CPU"
      hint "Software rendering is expected here (no GPU). Lower the desktop resolution (right-click -> System -> Set Resolution) if it feels slow."
      ;;
    hardware) ok "Rendering: HARDWARE (${PROBE_RENDERER:-${glx_renderer:-}})" ;;
    *)        warn "Rendering: UNKNOWN (renderer string masked or probe inconclusive)" ;;
  esac
}

check_display() {
  local xdpy parsed
  if [ -n "${DISPLAY_FOUND:-}" ] && command -v xdpyinfo >/dev/null 2>&1; then
    xdpy=$(DISPLAY="$DISPLAY_FOUND" xdpyinfo 2>/dev/null)
    parsed=$(parse_xdpy "$xdpy")
    if [ -n "$parsed" ]; then
      if ps -eo comm 2>/dev/null | grep -qE '^(Xtigervnc|Xvnc|Xorg)$'; then
        ok "Desktop resolution: ${parsed% *}, color depth: ${parsed#* }-bit (virtual VNC display)"
      else
        ok "Desktop resolution: ${parsed% *}, color depth: ${parsed#* }-bit"
      fi
      note "query: xdpyinfo on display $DISPLAY_FOUND"
    else
      bad "Could not read resolution/depth from display $DISPLAY_FOUND"
      hint "xdpyinfo returned no dimensions: the X server may be starting up; retry."
    fi
  else
    bad "No reachable X display - resolution and depth unknown"
    note "start the desktop (codespace port 6080) or run this from a terminal in the desktop"
    hint "No X display found: open the desktop in the browser (port 6080), or run desktop-doctor from a desktop terminal."
  fi
}

read_cpu_totals() { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat; }

check_cpu() {
  local t0 t1 usage_pct la limit high
  t0=($(read_cpu_totals)); sleep 1; t1=($(read_cpu_totals))
  if [ "${#t0[@]}" -eq 2 ] && [ "${t1[0]}" -gt "${t0[0]}" ] 2>/dev/null; then
    usage_pct=$(awk -v dt=$((t1[0]-t0[0])) -v di=$((t1[1]-t0[1])) \
      'BEGIN{printf "%.1f", (1-di/dt)*100}')
    ok "CPU usage: ${usage_pct}% (host, all cores, sampled over 1s)"
  else
    usage_pct=""
    warn "CPU usage: could not sample /proc/stat"
  fi
  note "cores visible: $(nproc 2>/dev/null || echo '?') (host view - the container may see all host cores)"
  la=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null) \
    && note "load average (1/5/15 min): $la"
  limit=$(parse_cgroup_cpu /sys/fs/cgroup)
  case "$limit" in
    none|unknown) note "container CPU limit: $limit" ;;
    *)           note "container CPU limit: $limit cores (cgroup)" ;;
  esac
  if [ -n "$usage_pct" ]; then
    high=$(awk -v u="$usage_pct" 'BEGIN{print (u>85)?1:0}')
    [ "$high" = 1 ] && hint "CPU usage is high: close heavy apps, or lower the desktop resolution."
  fi
}

check_memory() {
  local mem_total mem_avail cur max pct hot sw
  mem_total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
  mem_avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)
  if [ -n "$mem_total" ] && [ -n "$mem_avail" ]; then
    ok "host memory: $(awk -v t="$mem_total" -v a="$mem_avail" 'BEGIN{printf "%.1f/%.1f GiB used", (t-a)/1048576, t/1048576}')"
    note "host view from /proc/meminfo - the container limit below is the real ceiling"
  else
    warn "could not read /proc/meminfo"
  fi
  read -r cur max <<< "$(parse_cgroup_mem /sys/fs/cgroup)"
  if [ -n "${cur:-}" ]; then
    if [ "${max:-0}" -eq 0 ] 2>/dev/null; then
      ok "container memory: $(awk -v c="$cur" 'BEGIN{printf "%.2f", c/1073741824}') GiB used, no cgroup limit"
    else
      pct=$(awk -v c="$cur" -v m="$max" 'BEGIN{printf "%.1f", c*100/m}')
      ok "container memory: $(awk -v c="$cur" -v m="$max" 'BEGIN{printf "%.2f/%.2f GiB", c/1073741824, m/1073741824}') (${pct}%)"
      if [ -r /sys/fs/cgroup/memory.swap.current ]; then
        sw=$(cat /sys/fs/cgroup/memory.swap.current)
        [ "$sw" -gt 0 ] 2>/dev/null && note "container swap in use: $(awk -v s="$sw" 'BEGIN{printf "%.0f", s/1048576}') MiB"
      fi
      hot=$(awk -v p="$pct" 'BEGIN{print (p>90)?1:0}')
      [ "$hot" = 1 ] && hint "Container memory usage above 90%: back up ~/Files and delete unused codespaces; a rebuild restarts fresh."
    fi
  else
    warn "container memory limit unknown (no cgroup memory controller found)"
  fi
}

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

main() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --help) usage ;;
      --no-probe) ;;
      *) printf 'unknown option: %s (try --help)\n' "$arg" >&2; exit 2 ;;
    esac
  done

  WEBGL_STATUS="unknown"
  RENDER_TYPE="unknown"
  DISPLAY_FOUND=$(find_display)

  section "WebGL and rendering"
  check_webgl "$@"

  section "Display"
  check_display

  section "CPU"
  check_cpu

  section "Memory"
  check_memory

  section "Summary"
  printf '  checks passed: %d, warnings: %d, failures: %d\n' "$PASS" "$WARNED" "$FAILED"

  if [ "${#HINTS[@]}" -gt 0 ]; then
    printf '\n%sTroubleshooting:%s\n' "$C_HEAD" "$C_OFF"
    local i=0
    for i in "${!HINTS[@]}"; do
      printf '  %d. %s\n' "$((i+1))" "${HINTS[$i]}"
    done
  else
    note "nothing to troubleshoot - all checks passed"
  fi

  case "$WEBGL_STATUS" in
    unavailable) note "WebGL: unavailable - see hints above" ;;
    available)   note "WebGL: available ($RENDER_TYPE rendering, $PROBE_MODE probe)" ;;
    *)           note "WebGL: not verified - see hints above" ;;
  esac

  [ "$FAILED" -gt 0 ] && exit 1
  exit 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
DOCTOR
chmod +x "$BIN_DIR/desktop-doctor"

# --- Fluxbox menu entry, own managed block (50-menu.sh stays untouched) ------
MENU="$HOMEDIR/.fluxbox/menu"
if [ -f "$MENU" ]; then
  awk -v block='# >>> desktop-doctor >>>
[exec] (Diagnostics) {tilix -e desktop-doctor}
# <<< desktop-doctor <<<' '
    /^# >>> desktop-doctor >>>/ { inb = 1; next }
    /^# <<< desktop-doctor <<</ { inb = 0; next }
    inb { next }
    !done && /\[begin\]/ { print; print block; done = 1; next }
    { print }
  ' "$MENU" > "$MENU.new" && mv "$MENU.new" "$MENU"
fi
