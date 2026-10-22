#!/usr/bin/env bash
# 40-profiles.sh - encrypted save profile tool (desktop-profile).
# Split from setup.sh (section 3b); behavior unchanged.
# Uses: DATA_DIR BIN_DIR.
# ---------------------------------------------------------------------------
# 3b. Encrypted save profiles: password-protected archives that live on the
#     same desktop-data branch, so they sync between codespaces - including
#     codespaces run by different users. Only ciphertext is committed; the
#     passphrase is read from the terminal by 'age' and never stored, logged,
#     or sent anywhere. age derives the key with scrypt (N=2^18, ~256MB RAM
#     per guess, ~1s) - brute-forcing is infeasible for any long passphrase.
# ---------------------------------------------------------------------------
cat > "$BIN_DIR/desktop-profile" <<'PR'
#!/usr/bin/env bash
# Encrypted save profiles (see README). Only ciphertext is committed; the
# passphrase is read from the terminal by age and never stored or logged.
set -euo pipefail
DATA_DIR="${DESKTOP_DATA_DIR:-/workspaces/desktop-data}"
PROF_DIR="$DATA_DIR/profiles"
ACTION="${1:-}"
cd "$DATA_DIR"

# Fetch what other users pushed. list/restore read straight from the fetched
# state (FETCH_HEAD) - no merge, so local history and uncommitted files are
# never touched. save rebases on top of it only when a push collides.
fetch_origin() {
  git fetch -q origin desktop-data 2>/dev/null || true
}
profile_blob() { # <name> -> prints the encrypted profile from origin (or local)
  if git cat-file -e "FETCH_HEAD:profiles/$1.tar.gz.age" 2>/dev/null; then
    git show "FETCH_HEAD:profiles/$1.tar.gz.age"
  elif [ -f "$PROF_DIR/$1.tar.gz.age" ]; then
    cat "$PROF_DIR/$1.tar.gz.age"
  else
    return 1
  fi
}

case "$ACTION" in
  list)
    fetch_origin
    if git ls-tree -r --name-only FETCH_HEAD -- profiles/ 2>/dev/null | grep -q .; then
      git ls-tree -r --name-only FETCH_HEAD -- profiles/ | sed 's|.*/||;s|\.tar\.gz\.age$||'
    elif ls "$PROF_DIR"/*.age >/dev/null 2>&1; then
      ls -1 "$PROF_DIR"/*.age | sed 's|.*/||;s|\.tar\.gz\.age$||'
    else
      echo "(no encrypted profiles saved yet)"
    fi
    ;;
  save)
    if pgrep -x firefox >/dev/null; then
      echo "Firefox is running - close it first so the browser profile" >&2
      echo "(bookmarks, game saves) is archived consistently." >&2
      exit 1
    fi
    NAME="${2:-${GITHUB_USER:-}}"
    while [ -z "$NAME" ]; do read -rp "Profile name: " NAME; done
    # keep the name filesystem- and git-safe
    NAME=$(printf '%s' "$NAME" | tr -c 'a-zA-Z0-9._-' '-' | cut -c1-40)
    case "$NAME" in ""|"."|"..") echo "Invalid profile name." >&2; exit 1;; esac
    mkdir -p "$PROF_DIR"
    fetch_origin
    echo "This encrypts ~/Files plus the browser profile (bookmarks, game saves)"
    echo "and pushes ONLY the ciphertext to GitHub. Use a LONG passphrase - it is"
    echo "never stored anywhere; if you forget it, the profile is unrecoverable."
    TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
    # tar first, then encrypt to temp, then swap in atomically: a failure
    # anywhere leaves the previous saved profile untouched.
    tar -czf "$TMPD/profile.tar.gz" \
        --exclude='*/cache2' --exclude='*/startupCache' \
        --exclude='*/cache2/*' --exclude='*/startupCache/*' \
        files private/mozilla
    age -p -o "$TMPD/profile.tar.gz.age" "$TMPD/profile.tar.gz"
    mv -f "$TMPD/profile.tar.gz.age" "$PROF_DIR/$NAME.tar.gz.age"
    git add -A -- profiles/
    if ! git diff --cached --quiet -- profiles/; then
      git commit -qm "encrypted profile: $NAME ($(date -u +%Y-%m-%d_%H:%M))" -- profiles/
    fi
    if git push -q origin desktop-data 2>/tmp/profile-push.err; then
      echo "Profile '$NAME' saved (encrypted) and pushed to GitHub."
    else
      # Someone else saved first: replay our commit on top, keep local files.
      if git pull --rebase --autostash -q origin desktop-data 2>>/tmp/profile-push.err \
         && git push -q origin desktop-data 2>>/tmp/profile-push.err; then
        echo "Profile '$NAME' saved (encrypted) and pushed to GitHub."
      else
        echo "Push to GitHub FAILED:" >&2
        head -3 /tmp/profile-push.err >&2
        echo "The encrypted profile is committed locally - run this again later to retry." >&2
        exit 1
      fi
    fi
    ;;
  restore)
    if pgrep -x firefox >/dev/null; then
      echo "Firefox is running - close it first so the restored browser profile" >&2
      echo "is not overwritten by the live one." >&2
      exit 1
    fi
    NAME="${2:-}"
    fetch_origin
    if [ -z "$NAME" ]; then
      echo "Saved profiles:"
      "$0" list
      read -rp "Profile to restore: " NAME
    fi
    TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
    if ! profile_blob "$NAME" > "$TMPD/profile.tar.gz.age" 2>/dev/null; then
      echo "No profile '$NAME'. Try 'desktop-profile list'." >&2
      exit 1
    fi
    # age reads the passphrase from the terminal and writes nothing on a
    # wrong one, so a failed decrypt leaves the desktop untouched.
    if ! age -d -o "$TMPD/profile.tar.gz" "$TMPD/profile.tar.gz.age" 2>/tmp/profile-dec.err; then
      echo "Restore FAILED - wrong password or corrupted profile:" >&2
      grep -i "passphrase\|error" /tmp/profile-dec.err | head -1 >&2
      exit 1
    fi
    # Fully extract first; only a complete archive triggers the swap.
    mkdir -p "$TMPD/x"
    tar -xzf "$TMPD/profile.tar.gz" -C "$TMPD/x"
    # The profile REPLACES ~/Files and the browser profile (no mixing with
    # what is on this codespace). The previous state is kept locally.
    BK="$DATA_DIR/.pre-restore-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BK"
    [ -d files ] && mv files "$BK/files"
    [ -d private/mozilla ] && mv private/mozilla "$BK/private-mozilla"
    mkdir -p private
    # mv to the full target path: files/ was moved aside, so this is a rename
    mv "$TMPD/x/files" "$DATA_DIR/files"
    [ -d "$TMPD/x/private/mozilla" ] && mv "$TMPD/x/private/mozilla" "$DATA_DIR/private/mozilla"
    echo "Profile '$NAME' restored. Previous state kept in $BK (local only)."
    ;;
  *)
    echo "Usage: desktop-profile save [name]    encrypt ~/Files + browser data, push"
    echo "       desktop-profile restore [name]  decrypt a profile into this codespace"
    echo "       desktop-profile list            show saved profiles"
    exit 1
    ;;
esac
PR
chmod +x "$BIN_DIR/desktop-profile"
