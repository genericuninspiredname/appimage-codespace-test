#!/usr/bin/env bash
# Unit tests for the desktop-doctor diagnostics tool
# (branch diagnostics/webgl-and-rendering).
#
# Tests the PURE helpers (renderer classification, cgroup parsing, xdpyinfo
# parsing) by sourcing the tool, plus module idempotence (install + menu
# block) against an isolated fake $BIN_DIR/$HOMEDIR. No browser, X
# display, or built image is needed - the full tool is exercised in the
# codespace itself.
#
# The tool is extracted straight from the module that embeds it, so the
# tests always run the exact code that ships.
set -e

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
MODULE="$REPO/.devcontainer/modules/72-webgl-diagnostics.sh"
WORK=$(mktemp -d /tmp/desktop-doctor-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok: $*"; }

[ -f "$MODULE" ] || fail "module not found: $MODULE"

# --- extract the embedded tool and source it ---------------------------------
sed -n "/^cat > \"\$BIN_DIR\/desktop-doctor\" <<'DOCTOR'$/,/^DOCTOR$/p" "$MODULE" \
  | sed '1d;$d' > "$WORK/desktop-doctor"
bash -n "$WORK/desktop-doctor" || fail "tool has syntax errors"
# shellcheck source=/dev/null
source "$WORK/desktop-doctor"
command -v classify_renderer >/dev/null || fail "helpers not sourced"

# --- classify_renderer ---------------------------------------------------------
check() { # check <expected> <input>
  local got
  got=$(classify_renderer "$2")
  [ "$got" = "$1" ] || fail "classify_renderer('$2') = '$got', want '$1'"
  pass "classify_renderer('$2') -> $got"
}
check software "llvmpipe (LLVM 15.0.7, 256 bits)"
check software "softpipe"
check software "SWRAST"
check software "SwiftShader (software)"
check software "Software Rasterizer"
check software "ANGLE (Software, SwiftShader)"
check hardware "AMD Radeon RX 7900 XTX"
check hardware "virgl (virtual GPU)"
check unknown ""
check unknown "WebGL is disabled"
check unknown "unknown"

# --- parse_xdpy ---------------------------------------------------------------
xdpy_out='name of display:    :1
version number:    11.0
dimensions:    1280x800 pixels (341x212 millimeters)
depth of root window:    24 planes
number of screens:    1'
got=$(parse_xdpy "$xdpy_out")
[ "$got" = "1280x800 24" ] || fail "parse_xdpy -> '$got', want '1280x800 24'"
pass "parse_xdpy -> $got"
got=$(parse_xdpy "dimensions: 640x480 pixels" || true)
[ -z "$got" ] || fail "parse_xdpy should fail without depth, got '$got'"
pass "parse_xdpy rejects output without depth"

# --- parse_cgroup_cpu (v2 and v1 fixtures) -----------------------------------
mkdir -p "$WORK/cg2" "$WORK/cg1/cpu" "$WORK/cgnone"
printf '200000 100000\n' > "$WORK/cg2/cpu.max"
got=$(parse_cgroup_cpu "$WORK/cg2")
[ "$got" = "2.00" ] || fail "parse_cgroup_cpu v2 -> '$got', want '2.00'"
pass "parse_cgroup_cpu v2 quota -> $got cores"
printf 'max 100000\n' > "$WORK/cg2/cpu.max"
[ "$(parse_cgroup_cpu "$WORK/cg2")" = "none" ] || fail "v2 max should be none"
pass "parse_cgroup_cpu v2 max -> none"
printf '500000 100000\n' > "$WORK/cg1/cpu/cpu.cfs_quota_us"
printf '100000\n' > "$WORK/cg1/cpu/cpu.cfs_period_us"
[ "$(parse_cgroup_cpu "$WORK/cg1")" = "5.00" ] || fail "v1 quota wrong"
pass "parse_cgroup_cpu v1 quota -> 5.00 cores"
printf -- '-1\n' > "$WORK/cg1/cpu/cpu.cfs_quota_us"
[ "$(parse_cgroup_cpu "$WORK/cg1")" = "none" ] || fail "v1 unlimited wrong"
pass "parse_cgroup_cpu v1 -1 -> none"
[ "$(parse_cgroup_cpu "$WORK/cgnone")" = "unknown" ] || fail "missing controller should be unknown"
pass "parse_cgroup_cpu missing -> unknown"

# --- parse_cgroup_mem ---------------------------------------------------------
printf '1073741824\n' > "$WORK/cg2/memory.current"
printf '4294967296\n' > "$WORK/cg2/memory.max"
got=$(parse_cgroup_mem "$WORK/cg2")
[ "$got" = "1073741824 4294967296" ] || fail "parse_cgroup_mem -> '$got'"
pass "parse_cgroup_mem v2 -> $got"
printf 'max\n' > "$WORK/cg2/memory.max"
got=$(parse_cgroup_mem "$WORK/cg2")
[ "$got" = "1073741824 0" ] || fail "v2 max should map to 0, got '$got'"
pass "parse_cgroup_mem v2 max -> limit 0"
mkdir -p "$WORK/cg1/memory"
printf '9994244\n' > "$WORK/cg1/memory/memory.usage_in_bytes"
printf '9223372036854771712\n' > "$WORK/cg1/memory/memory.limit_in_bytes"
got=$(parse_cgroup_mem "$WORK/cg1")
[ "$got" = "9994244 0" ] || fail "v1 huge limit should map to 0, got '$got'"
pass "parse_cgroup_mem v1 huge limit -> 0"

# --- module idempotence: install + menu managed block ------------------------
export BIN_DIR="$WORK/bin" HOMEDIR="$WORK/home"
mkdir -p "$BIN_DIR" "$HOMEDIR/.fluxbox"
printf '[begin] (menu)\n  [exec] (xterm) {xterm}\n[end]\n' > "$HOMEDIR/.fluxbox/menu"

bash "$MODULE"
[ -x "$BIN_DIR/desktop-doctor" ] || fail "tool not installed"
bash -n "$BIN_DIR/desktop-doctor" || fail "installed tool has syntax errors"
grep -q 'Diagnostics' "$HOMEDIR/.fluxbox/menu" || fail "menu entry missing"
pass "module installs tool + menu entry"

menu_before=$(cat "$HOMEDIR/.fluxbox/menu")
bash "$MODULE"   # second run must be idempotent
[ "$(cat "$HOMEDIR/.fluxbox/menu")" = "$menu_before" ] || fail "menu changed on re-run"
n=$(grep -c 'desktop-doctor >>>' "$HOMEDIR/.fluxbox/menu")
[ "$n" -eq 1 ] || fail "managed block appears $n times, want 1"
pass "second module run is byte-identical, block appears once"

# tool must not run its report when sourced (already proven above) and
# must reject unknown options
if "$BIN_DIR/desktop-doctor" --bogus >/dev/null 2>&1; then
  fail "unknown option should exit non-zero"
fi
pass "--bogus rejected"

echo "PASS: diagnostics-test.sh"
