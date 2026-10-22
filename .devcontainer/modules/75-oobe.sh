#!/usr/bin/env bash
# 75-oobe.sh - first-run onboarding screen (welcome / OOBE).
#
# Installs the `desktop-welcome` one-shot dialog (no framework, no
# background service: it is launched once at start, shows the screen,
# and exits when closed) plus a Fluxbox menu entry of its own (managed
# block, like the diagnostics branch's - 50-menu.sh stays untouched).
# The screen shows the environment (Linux Codespace / Windows host /
# unknown), CPU, memory, screen resolution, WebGL status and backup
# status, with buttons for Browser, Files, WebGL Test, Performance
# Settings and Stop Instructions.
#
# First-launch gating lives in desktop-welcome --auto (launched by
# hooks/normal-start.d/10-oobe.sh): a marker in the persistent data
# dir ($DATA_DIR/.oobe-shown) makes it appear only on the first
# launch; the menu entry (or running `desktop-welcome`) reopens it any
# time. The marker is deliberately NOT part of what desktop-backup
# commits (it lives at the data dir root, outside files/), so a NEW
# codespace restored from a backup shows the screen again, while a
# rebuild does not re-show it.
#
# Uses the diagnostics interface from the diagnostics branch
# (desktop-doctor) when it is installed; the screen says so honestly
# when it is not.
# Uses: HOMEDIR DATA_DIR BIN_DIR.
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/desktop-welcome" <<'WELCOME'
#!/usr/bin/env bash
# desktop-welcome - first-run onboarding screen (OOBE) for the desktop.
#
# A lightweight, one-shot dialog: no framework, no daemon. Shows the
# environment (Codespace / Windows host / unknown), CPU, memory, screen
# resolution, WebGL status and backup status, plus buttons for Browser,
# Files, WebGL Test, Performance Settings and Stop Instructions.
#
# Usage: desktop-welcome [--auto] [--print] [--webgl-quick] [--help]
#   (no argument)  show the screen now (manual reopen - the Fluxbox
#                  menu entry "Welcome Screen" runs this)
#   --auto         first-launch mode: do nothing when the persistent
#                  marker ($DATA_DIR/.oobe-shown) exists, wait (bounded)
#                  for the X display, then show the screen once. The
#                  marker is written only after the dialog was really
#                  displayed, so a failed launch is retried next start.
#   --print        print the status text without any GUI (terminal use).
#   --webgl-quick  internal: fallback text shown by the WebGL Test
#                  button when desktop-doctor is not installed.
#
# Uses the `desktop-doctor` diagnostics interface (diagnostics branch)
# when it is installed; says so honestly when it is not. GLX renderer
# evidence is labeled as such - it is NOT a browser WebGL test.
set -u

DATA_DIR="${DESKTOP_DATA_DIR:-/workspaces/desktop-data}"
MARKER="$DATA_DIR/.oobe-shown"
MAX_WAIT="${DESKTOP_WELCOME_MAX_WAIT:-60}"          # seconds to wait for X
PROC_VERSION="${DESKTOP_WELCOME_PROC_VERSION:-$(cat /proc/version 2>/dev/null || true)}"
TOOL=""

# ------------------------------------------------------------- pure helpers
# (no side effects; exercised by tests/oobe-test.sh)

# detect_environment <CODESPACES> <CODESPACE_NAME> <proc-version> <uname-r>
#   -> "Linux (GitHub Codespace)" | "Windows host (WSL)" | "Unknown host ..."
# Codespaces evidence wins; without it, WSL markers in the kernel
# version mean "Linux under a Windows host". No evidence at all is
# reported as unknown - the host OS is not guessed.
detect_environment() {
  if [ "$1" = "true" ] || [ -n "$2" ]; then
    echo "Linux (GitHub Codespace)"
    return 0
  fi
  local combined
  combined=$(printf '%s\n%s\n' "${3:-}" "${4:-}" | tr '[:upper:]' '[:lower:]')
  case "$combined" in
    *microsoft*|*wsl*) echo "Windows host (WSL)" ;;
    *) echo "Unknown host (no Codespace or Windows evidence)" ;;
  esac
}

# classify_renderer <string> -> software | hardware | unknown
# Same rules as the diagnostics branch: generic/masked strings are not
# evidence; llvmpipe and friends are the CPU software rasterizers.
classify_renderer() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    ""|unknown|mozilla*|*"webgl is disabled"*|*generic*) echo "unknown" ;;
    *llvmpipe*|*softpipe*|*swrast*|*software*|*swiftshader*|*mesa\ offscreen*|*basic\ render*) echo "software" ;;
    *) echo "hardware" ;;
  esac
}

# parse_xdpy <xdpyinfo-output> -> "<WxH> <depth>" (empty when unusable)
parse_xdpy() {
  local dims depth
  dims=$(printf '%s\n' "$1" | awk '/dimensions:/{print $2; exit}')
  depth=$(printf '%s\n' "$1" | awk '/depth of root window:/{print $5; exit}')
  [ -n "$dims" ] && [ -n "$depth" ] && echo "$dims $depth"
}

# gib <kib> -> "<x.x>" (GiB, one decimal)
gib() { awk -v k="${1:-0}" 'BEGIN{printf "%.1f", k/1048576}'; }

# cgib <bytes> -> "<x.x>" (GiB, one decimal). cgroup memory files hold
# BYTES (unlike /proc/meminfo's KiB): feeding them to gib() would read
# 1024x too large.
cgib() { awk -v b="${1:-0}" 'BEGIN{printf "%.1f", b/1073741824}'; }

# fmt_cgroup_mem <cur-bytes> <max-bytes> -> the container memory line
fmt_cgroup_mem() { echo "$(cgib "${1:-0}")/$(cgib "${2:-0}") GiB container (cgroup limit)"; }

# backup_status <data-dir>: prints the honest backup state.
#  - a local backup commit is NOT proof of upload: push state is compared
#    against the last known remote ref (no network fetch happens here).
#  - only paths the backup tool actually saves (files/, .gitignore) are
#    checked, so unrelated files never read as "not backed up".
#  - git errors print "unknown", never "never backed up".
backup_status() {
  local dir="$1" out last count dirty unpushed
  if [ ! -d "$dir/.git" ]; then
    echo "Backup:  unknown (persistent data dir not initialized)"
    return 0
  fi
  if ! git -C "$dir" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    echo "Backup:  never run (the backup repository has no commits)"
    return 0
  fi
  if ! out=$(git -C "$dir" log --format='%s' -- files/ .gitignore 2>/dev/null); then
    echo "Backup:  unknown (could not read the backup repository)"
    return 0
  fi
  count=$(grep -c '^backup ' <<< "$out" || true)
  if [ "${count:-0}" -eq 0 ]; then
    echo "Backup:  never run (no backup commits found)"
  else
    last=$(git -C "$dir" log -1 --format=%ci --grep='^backup ' -- files/ .gitignore 2>/dev/null \
           | cut -d' ' -f1)
    echo "Backup:  last backup ${last:-unknown date} (${count} total)"
  fi
  dirty=$(git -C "$dir" status --porcelain -- files/ .gitignore 2>/dev/null | wc -l)
  [ "${dirty:-0}" -gt 0 ] 2>/dev/null \
    && echo "         ${dirty} uncommitted change(s) in ~/Files not backed up yet"
  if git -C "$dir" rev-parse -q --verify origin/desktop-data >/dev/null 2>&1; then
    # commits on the local branch that the last-known remote ref lacks
    unpushed=$(git -C "$dir" rev-list --count origin/desktop-data..desktop-data -- 2>/dev/null)
    if [ "${unpushed:-0}" -gt 0 ] 2>/dev/null; then
      echo "         latest backup not pushed to GitHub (local only)"
    else
      echo "         pushed to GitHub (last known remote state)"
    fi
  fi
}

# ------------------------------------------------------- display discovery
find_display() {
  local d
  for d in "${DESKTOP_WELCOME_DISPLAY:-}" "${DISPLAY:-}" :1 :0; do
    [ -n "$d" ] || continue
    if command -v xdpyinfo >/dev/null 2>&1; then
      DISPLAY="$d" xdpyinfo >/dev/null 2>&1 && { echo "$d"; return 0; }
    elif [ -e "/tmp/.X11-unix/X${d#:}" ]; then
      echo "$d"; return 0
    fi
  done
  return 1
}

# ------------------------------------------------------------ status text
# The body is rebuilt before every (re)display, so information stays
# current while the screen is open.
build_body() {
  local env_line cores cpu_model load cpu_limit
  local mem_total mem_avail mem_cur mem_max
  local disp="" parsed res_line webgl="WebGL:  unknown" glx_line=""
  local mem_host="" mem_cont=""

  env_line=$(detect_environment "${CODESPACES:-}" "${CODESPACE_NAME:-}" \
             "$PROC_VERSION" "$(uname -r 2>/dev/null || true)")

  cores=$(nproc 2>/dev/null || echo '?')
  cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null \
              | cut -d: -f2- | sed 's/^ *//;s/[[:space:]]*$//')
  load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)
  if [ -r /sys/fs/cgroup/cpu.max ]; then
    local q p
    read -r q p < /sys/fs/cgroup/cpu.max
    if [ "$q" = "max" ]; then cpu_limit="none"
    else cpu_limit=$(awk -v q="$q" -v p="$p" 'BEGIN{if(p>0)printf "%.1f cores", q/p; else print "unknown"}')
    fi
  else
    cpu_limit="unknown"
  fi

  mem_total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
  mem_avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)
  if [ -n "$mem_total" ] && [ -n "$mem_avail" ]; then
    mem_host="$(gib $((mem_total - mem_avail)))/$(gib "$mem_total") GiB host used, $(gib "$mem_avail") GiB available"
  else
    mem_host="unknown (could not read /proc/meminfo)"
  fi
  if [ -r /sys/fs/cgroup/memory.current ]; then
    mem_cur=$(cat /sys/fs/cgroup/memory.current)
    mem_max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
    if [ "$mem_max" = "max" ] || [ -z "$mem_max" ]; then
      # no cgroup limit: the "current" figure then reflects the whole
      # host, so it would be misleading as a container number
      mem_cont="no container memory limit (host view above)"
    else
      mem_cont=$(fmt_cgroup_mem "$mem_cur" "$mem_max")
    fi
  else
    mem_cont="container memory unknown (no cgroup memory controller)"
  fi

  disp=$(find_display) || true
  if [ -n "$disp" ] && command -v xdpyinfo >/dev/null 2>&1; then
    parsed=$(parse_xdpy "$(DISPLAY="$disp" xdpyinfo 2>/dev/null)")
    if [ -n "$parsed" ]; then
      res_line="${parsed% *}, ${parsed#* }-bit (display $disp)"
    else
      res_line="unknown (xdpyinfo returned no dimensions on $disp)"
    fi
  else
    res_line="unknown (no reachable X display)"
  fi

  # WebGL: the welcome keeps no test state and cannot know whether a
  # test ran before - say so instead of implying a one-time "not tested"
  # status. desktop-doctor (diagnostics branch) is the test tool; it also
  # keeps no result state (run-and-report), which is why nothing is
  # consumed here.
  if command -v desktop-doctor >/dev/null 2>&1; then
    webgl="WebGL:  no test result kept here - the WebGL Test button runs desktop-doctor"
  else
    webgl="WebGL:  no test result kept here - desktop-doctor (diagnostics branch)"
    webgl="$webgl is not installed;"
    webgl="$webgl WebGL Test falls back to a GLX renderer check (not a browser test)"
  fi

  # GLX renderer evidence, clearly labeled as such (not a browser test)
  if [ -n "$disp" ] && command -v glxinfo >/dev/null 2>&1; then
    local glx_renderer
    glx_renderer=$(DISPLAY="$disp" glxinfo -B 2>/dev/null \
                   | awk -F': *' '/OpenGL renderer string/{print $2; exit}')
    case "$(classify_renderer "$glx_renderer")" in
      software) glx_line="GLX:     software rendering ($glx_renderer)"
                glx_line="$glx_line - no GPU here, expected in a codespace" ;;
      hardware) glx_line="GLX:     hardware rendering ($glx_renderer)" ;;
      *)        glx_line="GLX:     unknown renderer (masked or no evidence)" ;;
    esac
  fi

  cat <<EOF
Welcome to your desktop - first-run overview

Environment: $env_line
CPU:         $cores cores ($cpu_model) - host view
             load (1/5/15 min): ${load:-unknown}
             container CPU limit: $cpu_limit
Memory:      $mem_host
             $mem_cont
Screen:      $res_line
$webgl
${glx_line:+$glx_line
}$(backup_status "$DATA_DIR")

Buttons below: Browser, Files, WebGL Test, Performance Settings,
Stop Instructions. Closing this window finishes onboarding (reopen it
any time: desktop menu -> Welcome Screen).
EOF
}

# ------------------------------------------------------------ dialog tooling
# GTK apps in this desktop need the session bus; the fluxbox session
# exports DBUS_SESSION_BUS_ADDRESS=autolaunch:, but this script may be
# launched by a start hook that lacks it. Default to autolaunch (X11
# based), never override an existing value.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-autolaunch:}"

pick_tool() {
  if command -v zenity >/dev/null 2>&1; then TOOL=zenity
  elif command -v xmessage >/dev/null 2>&1; then TOOL=xmessage
  else return 1
  fi
}

# launch_bg <cmd...>: run detached so the dialog stays responsive and
# the child survives this script's exit.
launch_bg() { nohup "$@" >/dev/null 2>&1 & }

# term_run <title> <command...>: open a terminal window running <command>.
# Prefers tilix (the desktop's standard terminal, same as the menu); tilix
# is known to exit immediately in some root setups, so its liveness is
# checked and xterm (always present) is the fallback.
term_run() {
  local title="$1"; shift
  if command -v tilix >/dev/null 2>&1; then
    nohup tilix -t "$title" -e "$@" >/dev/null 2>&1 &
    local tpid=$!
    sleep 1
    kill -0 "$tpid" 2>/dev/null && return 0
  fi
  command -v xterm >/dev/null 2>&1 || return 0
  nohup xterm -T "$title" -e "$@" >/dev/null 2>&1 &
}

# main_dialog: prints an action token (browser|files|webgl|perf|stop|close).
# Returns 2 when the dialog could not be displayed (caller must NOT mark
# the first launch done in that case).
main_dialog() {
  local body_file out rc action="" err_file err combined
  body_file=$(mktemp) || return 2
  build_body > "$body_file"
  if [ "$TOOL" = zenity ]; then
    # GTK question dialog: OK + Cancel + extra buttons. Extra-button
    # reporting differs across zenity versions, so BOTH streams are kept:
    #   zenity 4: extra button -> exit 1, label printed to STDOUT
    #             (Cancel and WM close also exit 1 but print no label;
    #              GTK warnings on stderr are ignored as noise)
    #   zenity 3: extra button -> exit 5, label printed to STDERR
    # A missing display also exits 1 but reports the error on stderr -
    # that is kept distinct from a plain close below.
    err_file=$(mktemp) || { rm -f "$body_file"; return 2; }
    out=$(zenity --question --title "Welcome to your desktop" --no-wrap \
          --text "$(cat "$body_file")" \
          --ok-label "Browser" --cancel-label "Close" \
          --extra-button "Files" \
          --extra-button "WebGL Test" \
          --extra-button "Performance Settings" \
          --extra-button "Stop Instructions" 2>"$err_file")
    rc=$?
    err=$(cat "$err_file" 2>/dev/null); rm -f "$err_file"
    combined="$out$err"
    case "$rc" in
      0) action=browser ;;
      1|5)
        case "$combined" in
          *"cannot open display"*|*"Unable to init"*|*"Cannot open display"*)
            rm -f "$body_file"; return 2 ;;
        esac
        case "$combined" in
          *Files*)                  action=files ;;
          *"WebGL Test"*)          action=webgl ;;
          *"Performance Settings"*) action=perf ;;
          *"Stop Instructions"*)    action=stop ;;
          *)
            # zenity 3 reports a timeout as exit 5 without a label;
            # treat it as "dialog failed" so onboarding retries later
            if [ "$rc" -eq 5 ]; then
              rm -f "$body_file"; return 2
            fi
            action=close ;;
        esac ;;
      *) rm -f "$body_file"; return 2 ;;
    esac
  else  # xmessage: one real button per action
    xmessage -title "Welcome to your desktop" -file "$body_file" \
      -buttons "Browser:101,Files:102,WebGL Test:103,Performance Settings:104,Stop Instructions:105,Close:0" \
      >/dev/null 2>&1
    rc=$?
    case "$rc" in
      101) action=browser ;; 102) action=files ;; 103) action=webgl ;;
      104) action=perf   ;; 105) action=stop   ;; 0)   action=close ;;
      *)   rm -f "$body_file"; return 2 ;;
    esac
  fi
  rm -f "$body_file"
  echo "$action"
}

# text_window <title> <ok-label> <textfile>: info window with a primary
# and a "Back" button. Returns 0 when the primary button was pressed.
text_window() {
  local title="$1" ok="$2" file="$3"
  if [ "$TOOL" = zenity ]; then
    zenity --text-info --title "$title" --filename "$file" --no-wrap \
           --ok-label "$ok" --cancel-label "Back" --width 560 --height 420 \
           >/dev/null 2>&1
  else
    xmessage -title "$title" -file "$file" -buttons "$ok:0,Back:1" >/dev/null 2>&1
    [ $? -eq 0 ]
  fi
}

# ------------------------------------------------------------- actions
do_action() {
  case "$1" in
    browser) launch_bg x-www-browser ;;
    files)   files_action ;;
    webgl)   webgl_test ;;
    perf)    perf_settings ;;
    stop)    stop_instructions ;;
  esac
}

files_action() {
  # nautilus works as root here too (it prints a root warning on stderr,
  # which is discarded; the window still opens - verified in the codespace)
  if command -v nautilus >/dev/null 2>&1; then
    launch_bg nautilus "$HOME/Files"
  else
    term_run "Files" bash -c \
      'cd "$HOME/Files" 2>/dev/null || cd "$HOME"; echo "~/Files:"; ls -laF; echo; printf "No graphical file manager found - this is a directory listing.\nPress Enter to close "; read -r _'
  fi
}

webgl_test() {
  if command -v desktop-doctor >/dev/null 2>&1; then
    # the diagnostics interface from the diagnostics branch
    term_run "WebGL Test" desktop-doctor
    return 0
  fi
  # fallback: honest message + GLX evidence in a terminal that stays open
  term_run "WebGL Test" "$0" --webgl-quick
}

webgl_quick_mode() {
  echo "Full WebGL browser test (desktop-doctor, from the diagnostics"
  echo "branch) is not installed here."
  echo
  echo "Quick GLX renderer check (evidence only - NOT a browser test):"
  local disp
  disp=$(find_display) || true
  if [ -n "$disp" ] && command -v glxinfo >/dev/null 2>&1; then
    DISPLAY="$disp" glxinfo -B 2>/dev/null | grep -E 'OpenGL (renderer|vendor)' \
      || echo "(glxinfo returned nothing)"
  else
    echo "(glxinfo unavailable, or no reachable X display)"
  fi
  echo
  printf 'Press Enter to close '
  read -r _
}

perf_settings() {
  local tmp
  tmp=$(mktemp) || return 0
  {
    echo "Performance settings"
    echo
    echo "Resolution: lower it to cut CPU load - the desktop renders in"
    echo "software (no GPU). Open the selector below (the same one as"
    echo "right-click -> System -> Set Resolution), or change the default"
    echo "via VNC_RESOLUTION in devcontainer.json."
    echo
    echo "Machine type: 2-core is the bare minimum; 4-core is much"
    echo "smoother for desktop + browser together. Change it on a STOPPED"
    echo "codespace (github.com/codespaces -> your codespace -> '...' ->"
    echo "Change machine type), then rebuild."
    echo
    echo "More tips: the Performance section of the project README."
  } > "$tmp"
  if text_window "Performance Settings" "Open Resolution Settings" "$tmp" \
     && [ -x /usr/local/bin/set-resolution ]; then
    # the desktop's actual resolution selector (same command as the menu)
    term_run "Set Resolution" bash /usr/local/bin/set-resolution
  fi
  rm -f "$tmp"
}

stop_instructions() {
  local tmp
  tmp=$(mktemp) || return 0
  {
    echo "Stopping the codespace - read-only instructions"
    echo
    echo "Stop for now (ends compute billing, keeps your files):"
    echo "    gh codespace stop"
    echo "    (add \"-c <name>\" from \"gh codespace list\", or use the web UI)"
    echo
    echo "Codespaces also stops it automatically after your idle timeout"
    echo "(default 30 min) - see github.com/settings/codespaces."
    echo
    echo "Delete for good (ALSO ends storage billing; ~/Files is lost"
    echo "unless backed up FIRST - menu -> Back Up Files):"
    echo "    gh codespace delete"
    echo
    echo "Closing this browser tab only disconnects the viewer - the"
    echo "codespace keeps running (and billing) until stopped or timed out."
  } > "$tmp"
  text_window "Stopping the codespace" "Close" "$tmp"
  rm -f "$tmp"
}

# ------------------------------------------------------------- show / run
show_welcome() {
  local action
  while :; do
    action=$(main_dialog) || return 2
    case "$action" in
      close)  return 0 ;;
      browser|files|webgl|perf|stop) do_action "$action" ;;
      *)      return 2 ;;
    esac
  done
}

run_welcome() { # <manual|auto>
  local rc
  pick_tool || { echo "desktop-welcome: no dialog tool (zenity/xmessage) found" >&2; return 1; }
  DISPLAY_FOUND=$(find_display) \
    || { echo "desktop-welcome: no reachable X display" >&2; return 1; }
  export DISPLAY="$DISPLAY_FOUND"
  show_welcome
  rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "desktop-welcome: dialog failed - first launch NOT marked done" >&2
    return 1
  fi
  # The dialog really ran: mark the first launch complete. The marker
  # lives in the persistent data dir (survives rebuilds) but outside
  # files/, so desktop-backup never commits it - a NEW codespace restored
  # from a backup shows the welcome again, a rebuild does not.
  mkdir -p "$DATA_DIR" 2>/dev/null || true
  touch "$MARKER" 2>/dev/null || true
  return 0
}

auto_mode() {
  [ -f "$MARKER" ] && { echo "welcome already shown - skipping"; exit 0; }
  mkdir -p "$DATA_DIR" 2>/dev/null || true
  # single instance via a lock DIRECTORY, deliberately not flock: a lock
  # held through a file descriptor would be inherited by every child -
  # e.g. the browser launched from the Browser button - and stay "held"
  # long after this script exits. A directory cannot be inherited; a
  # stale one (holder gone, or older than an hour) is stolen so a crash
  # never permanently wedges onboarding. /tmp, not the data dir: it is
  # transient runtime state, never persisted content.
  LOCK="${DESKTOP_WELCOME_LOCK:-/tmp/desktop-welcome.lock}"
  if ! mkdir "$LOCK" 2>/dev/null; then
    local holder
    holder=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -z "${holder:-}" ] || ! kill -0 "$holder" 2>/dev/null \
       || [ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
      rm -rf "$LOCK"
      mkdir "$LOCK" 2>/dev/null \
        || { echo "another welcome instance is running"; exit 0; }
    else
      echo "another welcome instance is running"; exit 0
    fi
  fi
  echo $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK"' EXIT
  # bounded wait for the desktop to come up (no background service -
  # if the display never appears, give up; the next start retries)
  local waited=0
  while [ "$waited" -lt "$MAX_WAIT" ]; do
    DISPLAY_FOUND=$(find_display) && break
    sleep 1
    waited=$((waited + 1))
  done
  if [ -z "${DISPLAY_FOUND:-}" ]; then
    echo "no X display within ${MAX_WAIT}s - will retry on the next start" >&2
    exit 1
  fi
  run_welcome auto
  exit $?
}

case "${1:-}" in
  --auto)        auto_mode ;;
  --print)      build_body ;;
  --webgl-quick) webgl_quick_mode ;;
  --classify-renderer) shift; classify_renderer "${1:-}" ;;  # test hook
  --cgroup-mem)      shift; fmt_cgroup_mem "${1:-0}" "${2:-0}" ;;  # test hook
  --help|-h)
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' ;;
  "")
    run_welcome manual ;;
  *)
    echo "unknown option: $1 (try --help)" >&2
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
WELCOME
chmod +x "$BIN_DIR/desktop-welcome"

# --- Fluxbox menu entry, own managed block (50-menu.sh stays untouched) ----
MENU="$HOMEDIR/.fluxbox/menu"
if [ -f "$MENU" ]; then
  awk -v block='# >>> desktop-oobe >>>
[exec] (Welcome Screen) {desktop-welcome}
# <<< desktop-oobe <<<' '
    /^# >>> desktop-oobe >>>/ { inb = 1; next }
    /^# <<< desktop-oobe <<</ { inb = 0; next }
    inb { next }
    !done && /\[begin\]/ { print; print block; done = 1; next }
    { print }
  ' "$MENU" > "$MENU.new" && mv "$MENU.new" "$MENU"
fi

# --- apply to a running desktop: module 70 restarts fluxbox BEFORE this
# module adds the menu entry, so restart once more here (same guard;
# keeps every window open, takes under a second). -------------------------
if pgrep -x fluxbox >/dev/null 2>&1; then
  DISPLAY="${DISPLAY:-:1}" fluxbox-remote restart >/dev/null 2>&1 || true
fi
