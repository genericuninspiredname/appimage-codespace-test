#!/usr/bin/env bash
# Backup / restore / encrypted-profile safety tests
# (storage/backup-and-profile-safety).
#
# Exercises desktop-profile and desktop-backup against an isolated fixture:
#   - save: personal files and browser secrets land in SEPARATE archives
#   - restore with a wrong passphrase: rejected, local data untouched
#   - restore of a corrupted archive: rejected, local data untouched
#   - restore of a structurally invalid archive: rejected, data untouched
#   - restore asks for confirmation; a cancelled restore changes nothing
#   - valid restore replaces ~/Files + browser profile, keeps a pre-restore
#     backup, and prunes old ones (retention)
#   - legacy single archives (files + browser together) still restore
#   - failed push: profile is kept locally, reported, and a retry pushes it
#   - desktop-backup: failed push keeps documents locally, retry uploads
#
# age reads passphrases from a terminal, so commands that hit an age prompt
# run under `script` (a pty) with the passphrase piped in. The fixture uses
# a bare repo as the GitHub stand-in. Nothing outside the temp dir is
# touched (GIT_CONFIG_GLOBAL is isolated; age and git see only $WORK).
set -e

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
WORK=$(mktemp -d /tmp/backup-profile-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v age >/dev/null 2>&1 || fail "age is required (it is part of the codespace image)"
command -v script >/dev/null 2>&1 || fail "script (util-linux) is required"

PASS='a long test passphrase'
# age -p asks for the passphrase twice (enter + confirm) per archive; a full
# save encrypts two archives, so feed enough lines for every prompt. Unused
# input lines are simply never read. age -d asks once per archive.
PASS_IN="$PASS
$PASS
$PASS
$PASS
"
PASS_DEC="$PASS
"          # age -d asks once per archive

# ---------------------------------------------------------------- fixture ---
git init -q --bare "$WORK/origin.git"
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"

install_tools() { # install_tools <home> <data> <bin> <remote>
  (
    cd "$1"
    export HOMEDIR="$1" DATA_DIR="$2" BIN_DIR="$3" REMOTE_URL="$4"
    # shellcheck source=/dev/null disable=SC2312
    . "$REPO/.devcontainer/modules/10-persistence.sh"
    # shellcheck source=/dev/null disable=SC2312
    . "$REPO/.devcontainer/modules/40-profiles.sh"
  ) >/dev/null
}

make_fixture() { # make_fixture <home> <data> <bin> <remote>
  # the home content is created AFTER the modules ran, so it lands directly
  # in ~/Files (a symlink into the data dir) exactly as a used codespace
  # would have it - not inside the first-start "Imported-from-home-*" dir
  mkdir -p "$1" "$2" "$3"
  install_tools "$@"
  mkdir -p "$1/Files/docs" "$1/.mozilla/firefox/abc.default-release"
  echo "hello"    > "$1/Files/docs/note.txt"
  echo "bookmark" > "$1/.mozilla/firefox/abc.default-release/bookmarks.json"
}

# pty_run <stdin-for-pty> <command>  -> runs command under a pty, rc preserved
pty_run() { printf '%s' "$1" | script -qec "$2" /dev/null; }

H="$WORK/home"; D="$WORK/data"; B="$WORK/bin"
make_fixture "$H" "$D" "$B" "file://$WORK/origin.git"
export DESKTOP_DATA_DIR="$D"
export PATH="$B:$PATH"

# --------------------------------------------------------------- 1. save ---
echo "== save: two separate archives, personal files kept apart from browser secrets"
OUT=$(pty_run "$PASS_IN" 'desktop-profile save t1' 2>&1) \
  || fail "save failed: $OUT"
[ -f "$D/profiles/t1.tar.gz.age" ]        || fail "personal archive missing"
[ -f "$D/profiles/t1.browser.tar.gz.age" ] || fail "browser archive missing"
# only ciphertext is committed: the working tree of the pushed branch
git -C "$WORK/origin.git" ls-tree -r --name-only desktop-data > "$WORK/pushed.txt"
grep -q '^profiles/t1\.tar\.gz\.age$'        "$WORK/pushed.txt" || fail "personal archive not pushed"
grep -q '^profiles/t1\.browser\.tar\.gz\.age$' "$WORK/pushed.txt" || fail "browser archive not pushed"
# separation: decrypt both and check contents (needs the passphrase via pty)
printf '%s' "$PASS_DEC" | script -qec "age -d -o $WORK/p.tar.gz $D/profiles/t1.tar.gz.age" /dev/null >/dev/null 2>&1 \
  || fail "personal archive does not decrypt with the save passphrase"
printf '%s' "$PASS_DEC" | script -qec "age -d -o $WORK/b.tar.gz $D/profiles/t1.browser.tar.gz.age" /dev/null >/dev/null 2>&1 \
  || fail "browser archive does not decrypt with the save passphrase"
tar -tzf "$WORK/p.tar.gz" | grep -q '^files/\?$'   || fail "personal archive lacks files/"
tar -tzf "$WORK/p.tar.gz" | grep -q 'mozilla'     && fail "personal archive contains browser secrets"
tar -tzf "$WORK/b.tar.gz" | grep -q '^private/mozilla' || fail "browser archive lacks private/mozilla"
tar -tzf "$WORK/b.tar.gz" | grep -qv 'mozilla'   && fail "browser archive contains non-mozilla data"
echo "   ok: personal and browser parts are separate, ciphertext-only pushed"

# --------------------------------------------- 2. wrong password on restore ---
echo "== wrong passphrase: restore must fail and leave local data untouched"
echo "local-change" > "$H/Files/docs/note.txt"
OUT=$(printf 'restore\nwrong passphrase\nwrong passphrase\n' \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  && fail "restore with wrong passphrase unexpectedly succeeded"
echo "$OUT" | grep -qi 'wrong password or corrupted' || fail "wrong-passphrase error not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "local-change" ] || fail "local data changed on wrong passphrase"
echo "   ok: rejected, data untouched"

# ----------------------------------------------- 3. corrupted archive restore ---
echo "== corrupted archive: restore must fail and leave local data untouched"
# corrupt the saved profile in the repo itself (commit + push the corrupted
# ciphertext): restore reads what is on the remote, so this is the realistic
# corruption scenario - a damaged profile that reached GitHub.
size=$(stat -c%s "$D/profiles/t1.tar.gz.age")
dd if=/dev/zero of="$D/profiles/t1.tar.gz.age" bs=1 seek=$((size / 2)) count=64 conv=notrunc status=none
git -C "$D" add profiles/ && git -C "$D" commit -qm 'test: corrupt saved profile' \
  && git -C "$D" push -q origin desktop-data
OUT=$(printf 'restore\n%s%s' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  && fail "restore of corrupted archive unexpectedly succeeded"
echo "$OUT" | grep -qi 'wrong password or corrupted' || fail "corruption not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "local-change" ] || fail "local data changed on corrupted archive"
echo "   ok: rejected, data untouched"

# ------------------------------------ 4. valid ciphertext, invalid structure ---
echo "== structurally invalid archive: refused even though it decrypts"
# replace the profile with a valid encryption of a tar.gz that contains no
# files/ and no private/mozilla - decrypts fine, but is not a profile
mkdir -p "$WORK/junk/strange"
echo x > "$WORK/junk/strange/thing"
tar -czf "$WORK/junk/strange.tar.gz" -C "$WORK/junk" strange
printf '%s' "$PASS_IN" | script -qec "age -p -o $WORK/junk/strange.tar.gz.age $WORK/junk/strange.tar.gz" /dev/null >/dev/null 2>&1
cp "$WORK/junk/strange.tar.gz.age" "$D/profiles/t1.tar.gz.age"
git -C "$D" add profiles/ && git -C "$D" commit -qm 'test: invalid profile structure' \
  && git -C "$D" push -q origin desktop-data
OUT=$(printf 'restore\n%s%s' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  && fail "restore of structurally invalid archive unexpectedly succeeded"
echo "$OUT" | grep -qi 'validation FAILED' || fail "structure validation not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "local-change" ] || fail "local data changed on invalid archive"
echo "   ok: refused, data untouched"

# ------------------------------------------------- 5. confirmation before restore ---
echo "== destructive restore asks first; cancelling changes nothing"
OUT=$(printf 'no\n' | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  && fail "restore without confirmation unexpectedly succeeded"
echo "$OUT" | grep -q "Type 'restore' to continue" || fail "confirmation prompt missing: $OUT"
echo "$OUT" | grep -q 'Cancelled - nothing was changed' || fail "cancel not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "local-change" ] || fail "local data changed on cancelled restore"
echo "   ok: prompt shown, cancel leaves data alone"
# --yes skips the prompt (for scripts); it must still validate (invalid archive -> fail)
OUT=$(printf '%s%s' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1 --yes' /dev/null 2>&1) \
  && fail "--yes restore of invalid archive unexpectedly succeeded"
echo "$OUT" | grep -qi 'validation FAILED' || fail "--yes did not validate: $OUT"
echo "   ok: --yes skips only the prompt, validation still runs"

# ------------------------------------------------------ 6. valid restore ---
echo "== valid restore replaces data, keeps a pre-restore backup"
# rebuild a clean profile first (the previous two cases deliberately broke it):
# reset the document to its saved content, then save + restore
[ "$(cat "$H/Files/docs/note.txt")" = "local-change" ] \
  || fail "prerequisite: expected the local change from the earlier cases"
echo "hello" > "$H/Files/docs/note.txt"
OUT=$(pty_run "$PASS_IN" 'desktop-profile save t1' 2>&1) || fail "re-save failed: $OUT"
OUT=$(printf 'restore\n%s%s' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  || fail "valid restore failed: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "hello" ] || fail "restored files wrong"
[ "$(cat "$H/.mozilla/firefox/abc.default-release/bookmarks.json")" = "bookmark" ] \
  || fail "restored browser profile wrong"
ls -d "$D"/.pre-restore-* >/dev/null 2>&1 || fail "pre-restore backup missing"
echo "   ok: data replaced, previous state kept locally"

# ----------------------------------------------- 7. retention (pruning) ---
echo "== retention: only the newest pre-restore backups are kept"
KEEP=5   # KEEP_PRE_RESTORE defaults to 3
for i in 1 2 3 4 5; do
  mkdir -p "$D/.pre-restore-2020010$i-000000"
done
N_BEFORE=$(ls -1d "$D"/.pre-restore-* 2>/dev/null | wc -l)
[ "$N_BEFORE" -ge 6 ] || fail "prerequisite: expected >=6 pre-restore dirs, got $N_BEFORE"
OUT=$(printf 'restore\n%s%s' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  || fail "restore (retention run) failed: $OUT"
N_AFTER=$(ls -1d "$D"/.pre-restore-* 2>/dev/null | wc -l)
[ "$N_AFTER" = 3 ] || fail "retention: expected 3 pre-restore dirs left, got $N_AFTER"
echo "$OUT" | grep -q 'Retention: kept the 3 most recent' || fail "retention note missing: $OUT"
# the kept ones must be the NEWEST (the freshly created one + 20200105, 20200104)
ls -1d "$D"/.pre-restore-* | grep -q '20200105' || fail "retention kept the wrong (old) dirs"
! ls -1d "$D"/.pre-restore-* | grep -q '20200101' || fail "retention left an old dir behind"
echo "   ok: pruned to the newest 3"

# ------------------------------------------------- 8. legacy single archive ---
echo "== legacy single archive (files + browser in one) still restores"
rm -rf "$D"/.pre-restore-*
mkdir -p "$WORK/legacy"
cp -rL "$H/Files" "$WORK/legacy/files"
mkdir -p "$WORK/legacy/private/mozilla/firefox/legacy.default"
echo "legacy-bookmark" > "$WORK/legacy/private/mozilla/firefox/legacy.default/bookmarks.json"
tar -czf "$WORK/legacy/legacy.tar.gz" -C "$WORK/legacy" files private/mozilla
printf '%s' "$PASS_IN" | script -qec "age -p -o $D/profiles/old.tar.gz.age $WORK/legacy/legacy.tar.gz" /dev/null >/dev/null 2>&1
echo "legacy-local-change" > "$H/Files/docs/note.txt"
OUT=$(printf 'restore\n%s' "$PASS_DEC" \
        | script -qec 'desktop-profile restore old' /dev/null 2>&1) \
  || fail "legacy restore failed: $OUT"
[ "$(cat "$H/.mozilla/firefox/legacy.default/bookmarks.json")" = "legacy-bookmark" ] \
  || fail "legacy browser profile not restored"
# the restore REPLACES the browser profile: the old one must be gone from
# the live tree (it is kept in the local .pre-restore-* backup)
[ -e "$H/.mozilla/firefox/abc.default-release" ] \
  && fail "legacy restore did not replace the old browser profile"
echo "$OUT" | grep -qi 'legacy' || fail "legacy archive not noted: $OUT"
# --files-only on a legacy archive: only documents, browser secrets left out
echo "legacy-local-change" > "$H/Files/docs/note.txt"
rm -rf "$H/.mozilla/firefox/legacy.default"
OUT=$(printf 'restore\n%s' "$PASS_DEC" \
        | script -qec 'desktop-profile restore old --files-only' /dev/null 2>&1) \
  || fail "legacy --files-only restore failed: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "hello" ] || fail "legacy --files-only did not restore files"
[ -e "$H/.mozilla/firefox/legacy.default" ] && fail "legacy --files-only touched browser secrets"
echo "   ok: legacy archives restore, and --files-only takes only documents"

# ------------------------------------------- 9. failed push + retry (profile) ---
echo "== failed push: profile kept locally, reported, retry uploads it"
git init -q --bare "$WORK/origin2.git"
H2="$WORK/home2"; D2="$WORK/data2"; B2="$WORK/bin2"
make_fixture "$H2" "$D2" "$B2" "file://$WORK/origin2.git"
DESKTOP_DATA_DIR_SAVE="$DESKTOP_DATA_DIR"; DESKTOP_DATA_DIR="$D2"; export DESKTOP_DATA_DIR
PATH_SAVE="$PATH"; export PATH="$B2:$PATH"
mv "$WORK/origin2.git" "$WORK/origin2.git.hidden"   # remote unreachable
OUT=$(pty_run "$PASS_IN" 'desktop-profile save t2' 2>&1) \
  && fail "save with unreachable remote unexpectedly succeeded"
echo "$OUT" | grep -q 'Push to GitHub FAILED' || fail "push failure not reported: $OUT"
echo "$OUT" | grep -Eq 'committed LOCALLY \([0-9]+ commit' || fail "pending commits not reported: $OUT"
[ -f "$D2/profiles/t2.tar.gz.age" ] || fail "profile lost after failed push"
git -C "$D2" rev-list --count origin/desktop-data..HEAD >/dev/null 2>&1 \
  && fail "unexpected remote-tracking ref after failed push"
mv "$WORK/origin2.git.hidden" "$WORK/origin2.git"   # remote back
OUT=$(script -qec 'desktop-profile push' /dev/null 2>&1) || fail "retry push failed: $OUT"
echo "$OUT" | grep -q 'Pushed' || fail "retry push did not report pushing: $OUT"
git -C "$WORK/origin2.git" ls-tree -r --name-only desktop-data | grep -q '^profiles/t2\.tar\.gz\.age$' \
  || fail "retried profile did not reach the remote"
OUT=$(script -qec 'desktop-profile status' /dev/null 2>&1) || fail "status failed: $OUT"
echo "$OUT" | grep -q 'Commits waiting to push: 0' || fail "status shows pending after successful push: $OUT"
echo "   ok: kept locally, retried, uploaded"

# --------------------------------------------- 10. failed push + retry (backup) ---
echo "== desktop-backup: failed push keeps documents locally, retry uploads them"
echo "doc" > "$H2/Files/doc.txt"
mv "$WORK/origin2.git" "$WORK/origin2.git.hidden"   # remote unreachable again
OUT=$(DESKTOP_DATA_DIR="$D2" desktop-backup 2>&1) \
  && fail "desktop-backup with unreachable remote unexpectedly succeeded"
echo "$OUT" | grep -q 'saved locally' || fail "backup push failure not reported: $OUT"
[ -n "$(git -C "$D2" log --oneline -- files/ 2>/dev/null)" ] || fail "documents not committed locally"
# a repeat run while the remote is still gone must keep everything and say so
OUT=$(DESKTOP_DATA_DIR="$D2" desktop-backup 2>&1) \
  && fail "backup retry succeeded with remote still gone"
echo "$OUT" | grep -Eq '[0-9]+ commit\(s\) waiting' || fail "pending count missing: $OUT"
mv "$WORK/origin2.git.hidden" "$WORK/origin2.git"   # remote back
OUT=$(DESKTOP_DATA_DIR="$D2" desktop-backup 2>&1) \
  || fail "backup retry after fix failed: $OUT"
echo "$OUT" | grep -q 'Pushed' || fail "backup retry did not report pushing pending commits: $OUT"
git -C "$WORK/origin2.git" ls-tree -r --name-only desktop-data -- files/ | grep -q 'files/doc.txt' \
  || fail "retried backup documents did not reach the remote"
echo "   ok: kept locally, retried, uploaded"

# ------------------------------------------ 11. separation of the plain backup ---
echo "== plain backup never includes credentials or browser secrets"
git -C "$WORK/origin2.git" ls-tree -r --name-only desktop-data > "$WORK/tree2.txt"
grep -q '^files/doc\.txt$' "$WORK/tree2.txt" || fail "documents not in plain backup"
grep -q 'private/' "$WORK/tree2.txt" && fail "credentials/private data leaked into plain backup"
grep -q 'profiles/' "$WORK/tree2.txt" || true   # profiles are ciphertext-only; presence is fine
git -C "$WORK/origin2.git" show desktop-data:.gitignore | grep -q '^private/$' \
  || fail ".gitignore no longer excludes private/"
echo "   ok: documents only"

export PATH="$PATH_SAVE"; export DESKTOP_DATA_DIR="$DESKTOP_DATA_DIR_SAVE"

echo "PASS: backup/restore/profile safety (wrong password, corrupted + invalid archives,"
echo "      confirmation, retention, legacy archives, failed push + retry)"
