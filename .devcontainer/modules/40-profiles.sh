#!/usr/bin/env bash
# 40-profiles.sh - encrypted save profile tool (desktop-profile).
# Split from setup.sh (section 3b). storage/backup-and-profile-safety:
# personal files and browser secrets are saved as SEPARATE encrypted
# archives (either can be restored alone), archives are validated before
# any local data is replaced, destructive restores ask for confirmation,
# failed pushes are reported with a retry path, and old pre-restore
# backups are pruned automatically (retention).
# Uses: DATA_DIR BIN_DIR.
# ---------------------------------------------------------------------------
# 3b. Encrypted save profiles: password-protected archives that live on the
#     same desktop-data branch, so they sync between codespaces - including
#     codespaces run by different users. Only ciphertext is committed; the
#     passphrase is read from the terminal by 'age' and never stored, logged,
#     or sent anywhere. age derives the key with scrypt (N=2^18, ~256MB RAM
#     per guess, ~1s) - brute-forcing is infeasible for any long passphrase.
#
#     Two archives per profile, so personal files stay separate from
#     credentials and browser secrets:
#       profiles/<name>.tar.gz.age         ~/Files (documents only)
#       profiles/<name>.browser.tar.gz.age browser profile (bookmarks,
#                                         logins, game saves)
#     Older single archives (files + browser in one ciphertext) still
#     restore; they are detected after decryption.
# ---------------------------------------------------------------------------
cat > "$BIN_DIR/desktop-profile" <<'PR'
#!/usr/bin/env bash
# Encrypted save profiles (see README). Only ciphertext is committed; the
# passphrase is read from the terminal by age and never stored or logged.
set -euo pipefail
DATA_DIR="${DESKTOP_DATA_DIR:-/workspaces/desktop-data}"
PROF_DIR="$DATA_DIR/profiles"
KEEP_PRE_RESTORE="${DESKTOP_KEEP_PRE_RESTORE:-3}"
ACTION="${1:-}"
cd "$DATA_DIR"

# Fetch what other users pushed. list/restore read straight from the fetched
# state (FETCH_HEAD) - no merge, so local history and uncommitted files are
# never touched. save/push rebases on top of it only when a push collides.
fetch_origin() {
  git fetch -q origin desktop-data 2>/dev/null || true
}
profile_blob() { # <name> <suffix> -> prints the encrypted profile from origin (or local)
  if git cat-file -e "FETCH_HEAD:profiles/$1$2" 2>/dev/null; then
    git show "FETCH_HEAD:profiles/$1$2"
  elif [ -f "$PROF_DIR/$1$2" ]; then
    cat "$PROF_DIR/$1$2"
  else
    return 1
  fi
}
unpushed_count() { # commits on desktop-data that GitHub does not have yet
  if git rev-parse -q --verify FETCH_HEAD >/dev/null 2>&1; then
    git rev-list --count FETCH_HEAD..HEAD 2>/dev/null || echo "?"
  else
    git rev-list --count --all --not --remotes 2>/dev/null || echo "?"
  fi
}
push_data() { # push desktop-data; on a collision, replay local commits on top
  if git push -q origin desktop-data 2>/tmp/profile-push.err; then return 0; fi
  if git pull --rebase --autostash -q origin desktop-data 2>>/tmp/profile-push.err \
     && git push -q origin desktop-data 2>>/tmp/profile-push.err; then
    return 0
  fi
  return 1
}
report_push_failure() {
  echo "Push to GitHub FAILED:" >&2
  head -3 /tmp/profile-push.err >&2
  echo "The encrypted profile is committed LOCALLY ($(unpushed_count) commit(s) waiting)" >&2
  echo "- run 'desktop-profile push' (or save again) later to retry." >&2
}
prune_pre_restore() { # keep only the newest $KEEP_PRE_RESTORE .pre-restore-* dirs
  local n=0 d removed=0
  while IFS= read -r d; do
    n=$((n + 1))
    if [ "$n" -gt "$KEEP_PRE_RESTORE" ]; then
      rm -rf "$d" && removed=$((removed + 1))
    fi
  done < <(ls -1dt "$DATA_DIR"/.pre-restore-* 2>/dev/null || true)
  if [ "$removed" -gt 0 ]; then
    echo "Retention: kept the $KEEP_PRE_RESTORE most recent pre-restore backup(s), removed $removed older one(s)."
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
  status)
    fetch_origin
    echo "Encrypted profiles (data dir: $DATA_DIR):"
    {
      git ls-tree -r --name-only FETCH_HEAD -- profiles/ 2>/dev/null | sed 's|^profiles/||'
      ls -1 "$PROF_DIR"/*.age 2>/dev/null | sed 's|.*/||'
    } | sed 's|\.browser\.tar\.gz\.age$||;s|\.tar\.gz\.age$||' | sort -u | while read -r n; do
      [ -n "$n" ] || continue
      where="remote only"
      [ -f "$PROF_DIR/$n.tar.gz.age" ] || [ -f "$PROF_DIR/$n.browser.tar.gz.age" ] && where="local + remote"
      git cat-file -e "FETCH_HEAD:profiles/$n.tar.gz.age" 2>/dev/null || where="local only"
      echo "  $n ($where)"
    done
    PENDING=$(unpushed_count)
    echo "Commits waiting to push: $PENDING"
    case "$PENDING" in
      0) : ;;
      "?") echo "Could not reach GitHub to compare - run 'desktop-profile status' again later." ;;
      *) echo "Run 'desktop-profile push' (or save again) to retry the upload." ;;
    esac
    ;;
  push)
    fetch_origin
    PENDING=$(unpushed_count)
    if [ "$PENDING" = 0 ]; then
      echo "Everything is already pushed to GitHub."
    elif push_data; then
      echo "Pushed $PENDING pending commit(s) to GitHub."
    else
      report_push_failure
      exit 1
    fi
    ;;
  save)
    if pgrep -x firefox >/dev/null; then
      echo "Firefox is running - close it first so the browser profile" >&2
      echo "(bookmarks, game saves) is archived consistently." >&2
      exit 1
    fi
    NAME="" NO_BROWSER=0
    shift || true
    for arg in "$@"; do
      case "$arg" in
        --no-browser) NO_BROWSER=1 ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) NAME="$arg" ;;
      esac
    done
    NAME="${NAME:-${GITHUB_USER:-}}"
    while [ -z "$NAME" ]; do read -rp "Profile name: " NAME; done
    # keep the name filesystem- and git-safe
    NAME=$(printf '%s' "$NAME" | tr -c 'a-zA-Z0-9._-' '-' | cut -c1-40)
    case "$NAME" in ""|"."|"..") echo "Invalid profile name." >&2; exit 1;; esac
    mkdir -p "$PROF_DIR"
    fetch_origin
    echo "This encrypts ~/Files plus the browser profile (bookmarks, game saves)"
    echo "and pushes ONLY the ciphertext to GitHub. Personal files and browser"
    echo "secrets are kept in two separate archives, so either can be restored"
    echo "alone. Use a LONG passphrase - it is never stored anywhere; if you"
    echo "forget it, the profile is unrecoverable."
    TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
    # tar first, then encrypt to temp, then swap in atomically: a failure
    # anywhere leaves the previous saved profile untouched.
    [ -d files ] || { echo "Nothing to save - ~/Files is missing." >&2; exit 1; }
    tar -czf "$TMPD/files.tar.gz" files
    age -p -o "$TMPD/files.tar.gz.age" "$TMPD/files.tar.gz"
    if [ "$NO_BROWSER" != 1 ] && [ -d private/mozilla ]; then
      tar -czf "$TMPD/browser.tar.gz" \
          --exclude='*/cache2' --exclude='*/startupCache' \
          --exclude='*/cache2/*' --exclude='*/startupCache/*' \
          private/mozilla
      age -p -o "$TMPD/browser.tar.gz.age" "$TMPD/browser.tar.gz"
      mv -f "$TMPD/browser.tar.gz.age" "$PROF_DIR/$NAME.browser.tar.gz.age"
    fi
    mv -f "$TMPD/files.tar.gz.age" "$PROF_DIR/$NAME.tar.gz.age"
    git add -A -- profiles/
    if ! git diff --cached --quiet -- profiles/; then
      git commit -qm "encrypted profile: $NAME ($(date -u +%Y-%m-%d_%H:%M))" -- profiles/
    fi
    if push_data; then
      echo "Profile '$NAME' saved (encrypted) and pushed to GitHub."
    else
      report_push_failure
      exit 1
    fi
    ;;
  restore)
    if pgrep -x firefox >/dev/null; then
      echo "Firefox is running - close it first so the restored browser profile" >&2
      echo "is not overwritten by the live one." >&2
      exit 1
    fi
    NAME="" FILES_ONLY=0 BROWSER_ONLY=0 ASSUME_YES=0
    shift || true
    for arg in "$@"; do
      case "$arg" in
        --files-only) FILES_ONLY=1 ;;
        --browser-only) BROWSER_ONLY=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) NAME="$arg" ;;
      esac
    done
    fetch_origin
    if [ -z "$NAME" ]; then
      echo "Saved profiles:"
      "$0" list
      read -rp "Profile to restore: " NAME
    fi
    TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
    # Locate the parts of the profile (remote first, local fallback).
    PERSONAL_OK=0 BROWSER_OK=0
    if profile_blob "$NAME" ".tar.gz.age" > "$TMPD/personal.tar.gz.age" 2>/dev/null; then
      PERSONAL_OK=1
    fi
    if profile_blob "$NAME" ".browser.tar.gz.age" > "$TMPD/browser.tar.gz.age" 2>/dev/null; then
      BROWSER_OK=1
    fi
    if [ "$PERSONAL_OK" = 0 ] && [ "$BROWSER_OK" = 0 ]; then
      echo "No profile '$NAME'. Try 'desktop-profile list'." >&2
      exit 1
    fi
    # What should be restored? --files-only/--browser-only restrict the
    # restore; by default everything present is restored.
    if [ "$BROWSER_ONLY" = 1 ]; then
      want_browser=1; want_files=0
      [ "$BROWSER_OK" = 0 ] && [ "$PERSONAL_OK" = 0 ] && { echo "Nothing to restore for this profile." >&2; exit 1; }
    elif [ "$FILES_ONLY" = 1 ]; then
      want_files=1; want_browser=0
      [ "$PERSONAL_OK" = 0 ] && { echo "Profile '$NAME' has no personal-files archive (browser secrets only)." >&2; exit 1; }
    else
      want_files=1; want_browser=1
    fi

    # Destructive operation: state exactly what will be replaced and get an
    # explicit confirmation before asking for the passphrase.
    PLAN_FILES=$want_files; PLAN_BROWSER=$want_browser
    if [ "$ASSUME_YES" != 1 ]; then
      echo "RESTORE will REPLACE this data on the codespace:"
      [ "$PLAN_FILES" = 1 ] && echo "  - ~/Files (every document currently in it)"
      [ "$PLAN_BROWSER" = 1 ] && echo "  - the browser profile (bookmarks, history, saved logins)"
      echo "The replaced state is kept in a local .pre-restore-* folder (never pushed)."
      read -rp "Type 'restore' to continue (anything else cancels): " ans
      if [ "$ans" != "restore" ]; then
        echo "Cancelled - nothing was changed." >&2
        exit 1
      fi
    fi

    # Decrypt the needed parts. A wrong passphrase or corrupted archive fails
    # here, BEFORE any local data is touched. The personal archive is also
    # decrypted for --browser-only when no separate browser archive exists:
    # older "legacy" profiles keep both parts in one ciphertext.
    DEC_PERSONAL=0 DEC_BROWSER=0
    if [ "$PERSONAL_OK" = 1 ]; then
      if [ "$BROWSER_ONLY" != 1 ] || [ "$BROWSER_OK" = 0 ]; then DEC_PERSONAL=1; fi
    fi
    if [ "$BROWSER_OK" = 1 ] && [ "$FILES_ONLY" != 1 ]; then DEC_BROWSER=1; fi
    if [ "$DEC_PERSONAL" = 0 ] && [ "$DEC_BROWSER" = 0 ]; then
      echo "Nothing to restore for this profile with --files-only/--browser-only." >&2
      exit 1
    fi
    if [ "$DEC_PERSONAL" = 1 ]; then
      if ! age -d -o "$TMPD/personal.tar.gz" "$TMPD/personal.tar.gz.age" 2>/tmp/profile-dec.err; then
        echo "Restore FAILED - wrong password or corrupted profile:" >&2
        grep -i "passphrase\|error" /tmp/profile-dec.err | head -1 >&2
        echo "Nothing was changed." >&2
        exit 1
      fi
    fi
    if [ "$DEC_BROWSER" = 1 ]; then
      if ! age -d -o "$TMPD/browser.tar.gz" "$TMPD/browser.tar.gz.age" 2>>/tmp/profile-dec.err; then
        echo "Restore FAILED - wrong password or corrupted profile:" >&2
        grep -i "passphrase\|error" /tmp/profile-dec.err | head -1 >&2
        echo "Nothing was changed." >&2
        exit 1
      fi
    fi

    # Validate BEFORE replacing local data: every archive must be a complete,
    # readable tar.gz with the expected structure. A tampered or truncated
    # archive stops the restore here.
    entries_of() { tar -tzf "$1" 2>/dev/null; }
    LEGACY=0
    if [ "$DEC_PERSONAL" = 1 ]; then
      ENTRIES=$(entries_of "$TMPD/personal.tar.gz") \
        || { echo "Validation FAILED: the personal archive is corrupted (not a complete tar.gz)." >&2; echo "Nothing was changed." >&2; exit 1; }
      # A personal archive must hold ~/Files, the browser profile, or both
      # (older "legacy" profiles kept files + browser secrets together).
      if printf '%s\n' "$ENTRIES" | grep -q '^files/\?$'; then
        printf '%s\n' "$ENTRIES" | grep -q '^private/mozilla' && LEGACY=1
      elif printf '%s\n' "$ENTRIES" | grep -q '^private/mozilla'; then
        LEGACY=1
      else
        echo "Validation FAILED: the personal archive contains neither ~/Files nor the browser profile - refusing to restore." >&2
        echo "Nothing was changed." >&2
        exit 1
      fi
    fi
    if [ "$DEC_BROWSER" = 1 ]; then
      BENTRIES=$(entries_of "$TMPD/browser.tar.gz") \
        || { echo "Validation FAILED: the browser archive is corrupted (not a complete tar.gz)." >&2; echo "Nothing was changed." >&2; exit 1; }
      printf '%s\n' "$BENTRIES" | grep -q '^private/mozilla' \
        || { echo "Validation FAILED: the browser archive does not contain the browser profile (private/mozilla)." >&2; echo "Nothing was changed." >&2; exit 1; }
    fi
    if [ "$LEGACY" = 1 ] && [ "$BROWSER_ONLY" = 1 ] && [ "$BROWSER_OK" = 0 ]; then
      echo "Note: '$NAME' is a legacy single archive - restoring the browser profile" >&2
      echo "from it also replaces ~/Files (the two are not separate in it)." >&2
      PLAN_FILES=1
    elif [ "$LEGACY" = 1 ] && [ "$BROWSER_ONLY" != 1 ] && [ "$FILES_ONLY" != 1 ]; then
      echo "Note: '$NAME' is a legacy single archive - personal files and browser" >&2
      echo "secrets are restored together. Save it again to split them into separate archives." >&2
    fi
    if [ "$LEGACY" = 1 ] && [ "$FILES_ONLY" = 1 ]; then
      echo "Note: '$NAME' is a legacy single archive; only ~/Files will be taken" >&2
      echo "from it - the browser secrets inside it are left out (--files-only)." >&2
      PLAN_BROWSER=0
    fi

    # Extract fully; only complete archives get this far. The separate
    # browser archive is extracted last so, in the rare case a legacy
    # archive and a separate browser archive coexist, the newer separate
    # archive wins the browser profile.
    mkdir -p "$TMPD/x"
    if [ "$DEC_PERSONAL" = 1 ]; then
      tar -xzf "$TMPD/personal.tar.gz" -C "$TMPD/x" \
        || { echo "Restore FAILED: the personal archive could not be extracted." >&2; echo "Nothing was changed." >&2; exit 1; }
    fi
    if [ "$DEC_BROWSER" = 1 ]; then
      tar -xzf "$TMPD/browser.tar.gz" -C "$TMPD/x" \
        || { echo "Restore FAILED: the browser archive could not be extracted." >&2; echo "Nothing was changed." >&2; exit 1; }
    fi

    # The profile REPLACES ~/Files and/or the browser profile (no mixing with
    # what is on this codespace). The previous state is kept locally, and if
    # any replace step fails everything is rolled back to that state.
    BK="$DATA_DIR/.pre-restore-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BK"
    MOVED_FILES=0 MOVED_BROWSER=0
    if [ "$PLAN_FILES" = 1 ] && [ -e files ]; then mv files "$BK/files"; MOVED_FILES=1; fi
    if [ "$PLAN_BROWSER" = 1 ] && [ -e private/mozilla ]; then mv private/mozilla "$BK/private-mozilla"; MOVED_BROWSER=1; fi
    mkdir -p private
    ok=1
    if [ "$PLAN_FILES" = 1 ]; then
      if [ -d "$TMPD/x/files" ]; then
        mv "$TMPD/x/files" files || ok=0
      else
        mkdir -p files
      fi
    fi
    if [ "$PLAN_BROWSER" = 1 ]; then
      if [ -d "$TMPD/x/private/mozilla" ]; then
        mv "$TMPD/x/private/mozilla" private/mozilla || ok=0
      else
        mkdir -p private/mozilla
      fi
    fi
    if [ "$ok" = 0 ]; then
      echo "Restore FAILED while replacing local data - rolling back." >&2
      [ "$PLAN_FILES" = 1 ] && [ -e files ] && rm -rf files
      [ "$PLAN_BROWSER" = 1 ] && [ -e private/mozilla ] && rm -rf private/mozilla
      if [ "$MOVED_FILES" = 1 ]; then mv "$BK/files" files; else [ "$PLAN_FILES" = 1 ] && mkdir -p files; fi
      if [ "$MOVED_BROWSER" = 1 ]; then mv "$BK/private-mozilla" private/mozilla; else [ "$PLAN_BROWSER" = 1 ] && mkdir -p private/mozilla; fi
      rmdir "$BK" 2>/dev/null || true
      exit 1
    fi
    echo "Profile '$NAME' restored. Previous state kept in $BK (local only)."
    prune_pre_restore
    ;;
  *)
    echo "Usage: desktop-profile save [name] [--no-browser]   encrypt ~/Files (+ browser profile), push"
    echo "       desktop-profile restore [name] [--files-only|--browser-only] [--yes]"
    echo "                          decrypt + validate a profile, then REPLACE local"
    echo "                          data (asks for confirmation first)"
    echo "       desktop-profile list      show saved profiles"
    echo "       desktop-profile status   profiles + commits waiting to push"
    echo "       desktop-profile push     retry pushing pending commits"
    exit 1
    ;;
esac
PR
chmod +x "$BIN_DIR/desktop-profile"
