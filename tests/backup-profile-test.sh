#!/usr/bin/env bash
# Backup / restore / encrypted-profile safety tests
# (storage/backup-and-profile-safety).
#
# Exercises desktop-profile and desktop-backup against an isolated fixture:
#   - save: personal files and browser secrets land in SEPARATE archives
#   - restore with a wrong passphrase: rejected, local data untouched
#   - restore of a corrupted archive: rejected, local data untouched
#   - restore of a structurally invalid archive: refused, data untouched
#   - restore of an archive with unsafe members (escaping links): refused
#   - valid personal + corrupt browser archive: BOTH parts untouched
#   - restore asks for confirmation; a cancelled restore changes nothing;
#     --yes skips only the prompt (validation still runs)
#   - valid restore replaces ~/Files + browser profile, keeps a pre-restore
#     backup with the previous contents, and prunes old ones (retention)
#   - personal-only profiles: default restore leaves the browser profile
#     alone; --browser-only on them is an error, not an empty restore
#   - legacy single archives (files + browser together) still restore,
#     including --files-only / --browser-only partial restores
#   - failed push: profile is kept locally, reported, and a retry pushes it
#   - a push collision with a conflicting profile: rebase is aborted cleanly,
#     pending commits are kept, nothing is lost
#   - desktop-backup: failed push keeps documents locally, retry uploads
#     them; pre-staged files (credentials) are never committed by a backup
#   - status/list work on an empty profile store
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
echo "bookmark2"   > "$H/.mozilla/firefox/abc.default-release/bookmarks.json"
OUT=$(printf 'wrong passphrase\nwrong passphrase\n' \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  && fail "restore with wrong passphrase unexpectedly succeeded"
echo "$OUT" | grep -qi 'wrong password or corrupted' || fail "wrong-passphrase error not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "local-change" ] || fail "local files changed on wrong passphrase"
[ "$(cat "$H/.mozilla/firefox/abc.default-release/bookmarks.json")" = "bookmark2" ] \
  || fail "local browser data changed on wrong passphrase"
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
OUT=$(printf '%s%s' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  && fail "restore of corrupted archive unexpectedly succeeded"
echo "$OUT" | grep -qi 'wrong password or corrupted' || fail "corruption not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "local-change" ] || fail "local files changed on corrupted archive"
echo "   ok: rejected, data untouched"
# rebuild a clean t1 (the corruption test deliberately broke it): reset the
# live data to the saved content first so the profile holds known values
printf 'hello\n'    > "$H/Files/docs/note.txt"
printf 'bookmark\n' > "$H/.mozilla/firefox/abc.default-release/bookmarks.json"
OUT=$(pty_run "$PASS_IN" 'desktop-profile save t1' 2>&1) || fail "re-save failed: $OUT"

# ------------------------------------ 4. valid ciphertext, invalid structure ---
echo "== structurally invalid archive: refused even though it decrypts"
# a separate 'bad' profile: a valid encryption of a tar.gz that contains no
# files/ and no private/mozilla - decrypts fine, but is not a profile
mkdir -p "$WORK/junk/strange"
echo x > "$WORK/junk/strange/thing"
tar -czf "$WORK/junk/strange.tar.gz" -C "$WORK/junk" strange
printf '%s' "$PASS_IN" | script -qec "age -p -o $D/profiles/bad.tar.gz.age $WORK/junk/strange.tar.gz" /dev/null >/dev/null 2>&1
git -C "$D" add profiles/ && git -C "$D" commit -qm 'test: invalid profile structure' \
  && git -C "$D" push -q origin desktop-data
OUT=$(printf '%s' "$PASS_DEC" \
        | script -qec 'desktop-profile restore bad' /dev/null 2>&1) \
  && fail "restore of structurally invalid archive unexpectedly succeeded"
echo "$OUT" | grep -qi 'Validation FAILED' || fail "structure validation not reported: $OUT"
echo "$OUT" | grep -qi 'contains neither' || fail "invalid-structure reason not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "hello" ] || fail "local data changed on invalid archive"
echo "   ok: refused, data untouched"

# --------------------------------------------- 4b. unsafe archive members ---
echo "== unsafe archive members (escaping symlink): refused before extraction"
# a separate 'evil' profile: valid tar.gz with files/ but also a symlink
# whose target escapes the archive - must never be extracted as-is
mkdir -p "$WORK/evil/files/docs"
echo "evil" > "$WORK/evil/files/docs/note.txt"
ln -s /etc/passwd "$WORK/evil/files/escape"
tar -czf "$WORK/evil/evil.tar.gz" -C "$WORK/evil" files
printf '%s' "$PASS_IN" | script -qec "age -p -o $D/profiles/evil.tar.gz.age $WORK/evil/evil.tar.gz" /dev/null >/dev/null 2>&1
git -C "$D" add profiles/ && git -C "$D" commit -qm 'test: unsafe profile members' \
  && git -C "$D" push -q origin desktop-data
OUT=$(printf '%s' "$PASS_DEC" \
        | script -qec 'desktop-profile restore evil' /dev/null 2>&1) \
  && fail "restore of archive with unsafe members unexpectedly succeeded"
echo "$OUT" | grep -qi 'unsafe member' || fail "unsafe member not reported: $OUT"
echo "$OUT" | grep -q 'link target escapes' || fail "escape reason not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "hello" ] || fail "local data changed on unsafe archive"
[ "$(cat "$H/.mozilla/firefox/abc.default-release/bookmarks.json")" = "bookmark" ] \
  || fail "local browser data changed on unsafe archive"
echo "   ok: refused, data untouched"

# ------------------------------------------------- 5. confirmation before restore ---
echo "== destructive restore asks first; cancelling changes nothing"
OUT=$(printf '%s%sno\n' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  && fail "restore without confirmation unexpectedly succeeded"
echo "$OUT" | grep -q "Type 'restore' to continue" || fail "confirmation prompt missing: $OUT"
echo "$OUT" | grep -q 'Cancelled - nothing was changed' || fail "cancel not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "hello" ] || fail "local files changed on cancelled restore"
[ "$(cat "$H/.mozilla/firefox/abc.default-release/bookmarks.json")" = "bookmark" ] \
  || fail "local browser data changed on cancelled restore"
echo "   ok: prompt shown, cancel leaves data alone"
# --yes skips the prompt (for scripts) but must NOT skip validation
OUT=$(printf '%s' "$PASS_DEC" \
        | script -qec 'desktop-profile restore bad --yes' /dev/null 2>&1) \
  && fail "--yes restore of invalid archive unexpectedly succeeded"
echo "$OUT" | grep -qi 'Validation FAILED' || fail "--yes did not validate: $OUT"
echo "   ok: --yes skips only the prompt, validation still runs"

# ------------------------------------------------------ 6. valid restore ---
echo "== valid restore replaces data, keeps a pre-restore backup with the old contents"
# modify BOTH live parts after the save, so the restore provably replaces
# them and the pre-restore backup provably holds the previous state
echo "pre-restore-state"    > "$H/Files/docs/note.txt"
echo "pre-restore-bookmark" > "$H/.mozilla/firefox/abc.default-release/bookmarks.json"
OUT=$(printf '%s%srestore\n' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  || fail "valid restore failed: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "hello" ] || fail "restored files wrong"
[ "$(cat "$H/.mozilla/firefox/abc.default-release/bookmarks.json")" = "bookmark" ] \
  || fail "restored browser profile wrong"
ls -d "$D"/.pre-restore-* >/dev/null 2>&1 || fail "pre-restore backup missing"
# the pre-restore backup must hold the previous (replaced) contents
[ "$(cat "$D"/.pre-restore-*/files/docs/note.txt 2>/dev/null)" = "pre-restore-state" ] \
  || fail "pre-restore backup lost the previous documents"
[ "$(cat "$D"/.pre-restore-*/private-mozilla/firefox/abc.default-release/bookmarks.json 2>/dev/null)" = "pre-restore-bookmark" ] \
  || fail "pre-restore backup lost the previous browser data"
echo "   ok: data replaced, previous state kept locally"

# ----------------------------------------------- 7. retention (pruning) ---
echo "== retention: only the newest pre-restore backups are kept"
for i in 1 2 3 4 5; do
  mkdir -p "$D/.pre-restore-2020010$i-000000"
done
N_BEFORE=$(ls -1d "$D"/.pre-restore-* 2>/dev/null | wc -l)
[ "$N_BEFORE" -ge 6 ] || fail "prerequisite: expected >=6 pre-restore dirs, got $N_BEFORE"
OUT=$(printf '%s%srestore\n' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  || fail "restore (retention run) failed: $OUT"
N_AFTER=$(ls -1d "$D"/.pre-restore-* 2>/dev/null | wc -l)
[ "$N_AFTER" = 3 ] || fail "retention: expected 3 pre-restore dirs left, got $N_AFTER"
echo "$OUT" | grep -q 'Retention: kept the 3 most recent' || fail "retention note missing: $OUT"
# the kept ones must be the NEWEST (the freshly created one + 20200105, 20200104)
ls -1d "$D"/.pre-restore-* | grep -q '20200105' || fail "retention kept the wrong (old) dirs"
! ls -1d "$D"/.pre-restore-* | grep -q '20200101' || fail "retention left an old dir behind"
echo "   ok: pruned to the newest 3"

# ------------------------------------- 8. valid personal + corrupt browser ---
echo "== mixed validity: valid personal + corrupted browser leaves BOTH parts untouched"
# corrupt only the browser archive (commit + push, as a repo-side corruption)
size=$(stat -c%s "$D/profiles/t1.browser.tar.gz.age")
dd if=/dev/zero of="$D/profiles/t1.browser.tar.gz.age" bs=1 seek=$((size / 2)) count=64 conv=notrunc status=none
git -C "$D" add profiles/ && git -C "$D" commit -qm 'test: corrupt browser archive' \
  && git -C "$D" push -q origin desktop-data
echo "mixed-change" > "$H/Files/docs/note.txt"
OUT=$(printf '%s%s' "$PASS_DEC" "$PASS_DEC" \
        | script -qec 'desktop-profile restore t1' /dev/null 2>&1) \
  && fail "restore with corrupt browser archive unexpectedly succeeded"
echo "$OUT" | grep -qi 'wrong password or corrupted' || fail "browser corruption not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "mixed-change" ] \
  || fail "files were touched although the browser archive was corrupt"
echo "   ok: all-or-nothing - nothing replaced"
# rebuild a clean t1 again (same reset as above)
printf 'hello\n'    > "$H/Files/docs/note.txt"
printf 'bookmark\n' > "$H/.mozilla/firefox/abc.default-release/bookmarks.json"
OUT=$(pty_run "$PASS_IN" 'desktop-profile save t1' 2>&1) || fail "re-save failed: $OUT"

# --------------------------------------------- 9. personal-only profiles ---
echo "== personal-only profile: default restore leaves the browser profile alone"
OUT=$(pty_run "$PASS_IN" 'desktop-profile save t3 --no-browser' 2>&1) || fail "save --no-browser failed: $OUT"
[ -f "$D/profiles/t3.tar.gz.age" ] || fail "t3 personal archive missing"
[ -f "$D/profiles/t3.browser.tar.gz.age" ] && fail "t3 browser archive unexpectedly exists"
echo "t3-change"    > "$H/Files/docs/note.txt"
echo "bookmark-t3"  > "$H/.mozilla/firefox/abc.default-release/bookmarks.json"
OUT=$(printf '%srestore\n%s' "$PASS_DEC" \
        | script -qec 'desktop-profile restore t3' /dev/null 2>&1) \
  || fail "restore of personal-only profile failed: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "hello" ] || fail "personal-only restore did not replace files"
[ "$(cat "$H/.mozilla/firefox/abc.default-release/bookmarks.json")" = "bookmark-t3" ] \
  || fail "personal-only restore touched the browser profile"
echo "$OUT" | grep -q 'no browser part' || fail "missing-part note not shown: $OUT"
echo "   ok: files replaced, browser profile untouched, noted"
# --browser-only on a personal-only profile: an error, not an empty restore
echo "t3-change2" > "$H/Files/docs/note.txt"
OUT=$(printf '%s' "$PASS_DEC" \
        | script -qec 'desktop-profile restore t3 --browser-only' /dev/null 2>&1) \
  && fail "--browser-only on personal-only profile unexpectedly succeeded"
echo "$OUT" | grep -q 'has no browser part' || fail "missing browser part not reported: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "t3-change2" ] || fail "data changed on --browser-only error"
echo "   ok: refused, data untouched"

# ------------------------------------------------- 10. legacy single archive ---
echo "== legacy single archive (files + browser in one) still restores"
rm -rf "$D"/.pre-restore-*
mkdir -p "$WORK/legacy"
cp -rL "$H/Files" "$WORK/legacy/files"
mkdir -p "$WORK/legacy/private/mozilla/firefox/legacy.default"
echo "legacy-bookmark" > "$WORK/legacy/private/mozilla/firefox/legacy.default/bookmarks.json"
tar -czf "$WORK/legacy/legacy.tar.gz" -C "$WORK/legacy" files private/mozilla
printf '%s' "$PASS_IN" | script -qec "age -p -o $D/profiles/old.tar.gz.age $WORK/legacy/legacy.tar.gz" /dev/null >/dev/null 2>&1
echo "legacy-local-change" > "$H/Files/docs/note.txt"
OUT=$(printf '%srestore\n' "$PASS_DEC" \
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
OUT=$(printf '%srestore\n' "$PASS_DEC" \
        | script -qec 'desktop-profile restore old --files-only' /dev/null 2>&1) \
  || fail "legacy --files-only restore failed: $OUT"
# the legacy archive was built from the then-current ~/Files (note.txt held
# "t3-change2" from the personal-only test above) - that is what must return
[ "$(cat "$H/Files/docs/note.txt")" = "t3-change2" ] || fail "legacy --files-only did not restore files"
[ -e "$H/.mozilla/firefox/legacy.default" ] && fail "legacy --files-only touched browser secrets"
echo "   ok: legacy archives restore, and --files-only takes only documents"
# --browser-only on a legacy archive: only browser data, ~/Files left alone
echo "legacy-files-untouched" > "$H/Files/docs/note.txt"
mkdir -p "$H/.mozilla/firefox/legacy.default"
OUT=$(printf '%srestore\n' "$PASS_DEC" \
        | script -qec 'desktop-profile restore old --browser-only' /dev/null 2>&1) \
  || fail "legacy --browser-only restore failed: $OUT"
[ "$(cat "$H/Files/docs/note.txt")" = "legacy-files-untouched" ] \
  || fail "legacy --browser-only replaced ~/Files despite promising not to"
[ -f "$H/.mozilla/firefox/legacy.default/bookmarks.json" ] \
  || fail "legacy --browser-only did not restore the browser part"
echo "$OUT" | grep -q 'legacy single archive; only the browser part' \
  || fail "legacy --browser-only note missing: $OUT"
echo "   ok: legacy --browser-only restores only browser data"

# ------------------------------------------- 11. failed push + retry (profile) ---
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
mv "$WORK/origin2.git.hidden" "$WORK/origin2.git"   # remote back
OUT=$(script -qec 'desktop-profile push' /dev/null 2>&1) || fail "retry push failed: $OUT"
echo "$OUT" | grep -q 'Pushed' || fail "retry push did not report pushing: $OUT"
git -C "$WORK/origin2.git" ls-tree -r --name-only desktop-data | grep -q '^profiles/t2\.tar\.gz\.age$' \
  || fail "retried profile did not reach the remote"
OUT=$(script -qec 'desktop-profile status' /dev/null 2>&1) || fail "status failed: $OUT"
echo "$OUT" | grep -q 'Commits waiting to push: 0' || fail "status shows pending after successful push: $OUT"
echo "   ok: kept locally, retried, uploaded"

# ------------------------------- 11b. push collision with a conflicting profile ---
echo "== push collision on the same profile: rebase aborted cleanly, nothing lost"
git init -q --bare "$WORK/origin3.git"
H3="$WORK/home3"; D3="$WORK/data3"; B3="$WORK/bin3"
make_fixture "$H3" "$D3" "$B3" "file://$WORK/origin3.git"
export PATH="$B3:$PATH_SAVE"    # keep t2 tools; t3 tools shadow for its calls
DESKTOP_DATA_DIR="$D3"; export DESKTOP_DATA_DIR
echo "v1" > "$H3/Files/docs/note.txt"
OUT=$(pty_run "$PASS_IN" 'desktop-profile save conf' 2>&1) || fail "conf v1 save failed: $OUT"
# a second codespace (fixture 4) starts from v1, while the first saves v2
H4="$WORK/home4"; D4="$WORK/data4"; B4="$WORK/bin4"
make_fixture "$H4" "$D4" "$B4" "file://$WORK/origin3.git"
echo "v2" > "$H3/Files/docs/note.txt"
DESKTOP_DATA_DIR="$D3"; export DESKTOP_DATA_DIR
OUT=$(pty_run "$PASS_IN" 'desktop-profile save conf' 2>&1) || fail "conf v2 save failed: $OUT"
# codespace 2 (still at v1) saves a different conf -> push collides, rebase
# conflicts on the same profile file
echo "v3" > "$H4/Files/docs/note.txt"
DESKTOP_DATA_DIR="$D4"; export DESKTOP_DATA_DIR
OUT=$(pty_run "$PASS_IN" 'desktop-profile save conf' 2>&1) \
  && fail "conflicting save unexpectedly succeeded"
echo "$OUT" | grep -q 'Push to GitHub FAILED' || fail "collision not reported: $OUT"
# the repo must NOT be left mid-rebase
if [ -d "$D4/.git/rebase-merge" ] || [ -d "$D4/.git/rebase-apply" ]; then
  fail "repo left mid-rebase after conflicting push"
fi
# the pending commit and the local profile must still be there
[ -f "$D4/profiles/conf.tar.gz.age" ] || fail "local profile lost after collision"
git -C "$D4" log --oneline | grep -q 'encrypted profile: conf' \
  || fail "pending commit lost after collision"
# the tracked profile tree must be clean (the fixture's files/ dir was never
# committed in this scenario, so only profiles/ is tracked here)
git -C "$D4" status --short -- profiles/ | grep -q . \
  && fail "profile tree dirt after collision: $(git -C "$D4" status --short -- profiles/)"
echo "   ok: rebase aborted, pending commit + profile kept, reported"

# --------------------------------------------- 12. failed push + retry (backup) ---
echo "== desktop-backup: failed push keeps documents locally, retry uploads them"
DESKTOP_DATA_DIR="$D2"; export DESKTOP_DATA_DIR
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

# --------------------------- 13. pre-staged files are never committed by a backup ---
echo "== desktop-backup never commits files it did not stage itself"
echo "secret-api-key" > "$D2/stray.creds"
git -C "$D2" add stray.creds          # e.g. a user staging credentials by accident
OUT=$(DESKTOP_DATA_DIR="$D2" desktop-backup 2>&1) || fail "backup with pre-staged file failed: $OUT"
git -C "$WORK/origin2.git" ls-tree -r --name-only desktop-data > "$WORK/tree2.txt"
grep -q 'stray.creds' "$WORK/tree2.txt" && fail "pre-staged credentials were committed by the backup"
git -C "$D2" diff --cached --name-only | grep -q 'stray.creds' \
  || fail "pre-staged file was silently unstaged instead of left alone"
git -C "$D2" rm --cached -q stray.creds; rm -f "$D2/stray.creds"   # clean up
echo "   ok: left staged locally, not committed, not pushed"

# ------------------------------------------ 14. separation of the plain backup ---
echo "== plain backup never includes credentials or browser secrets"
git -C "$WORK/origin2.git" ls-tree -r --name-only desktop-data > "$WORK/tree2.txt"
grep -q '^files/doc\.txt$' "$WORK/tree2.txt" || fail "documents not in plain backup"
grep -q 'private/' "$WORK/tree2.txt" && fail "credentials/private data leaked into plain backup"
git -C "$WORK/origin2.git" show desktop-data:.gitignore | grep -q '^private/$' \
  || fail ".gitignore no longer excludes private/"
echo "   ok: documents only"

# ------------------------------------------------- 15. empty profile store ---
echo "== list/status on an empty profile store"
git init -q --bare "$WORK/origin5.git"
H5="$WORK/home5"; D5="$WORK/data5"; B5="$WORK/bin5"
make_fixture "$H5" "$D5" "$B5" "file://$WORK/origin5.git"
DESKTOP_DATA_DIR="$D5"; export DESKTOP_DATA_DIR
export PATH="$B5:$PATH_SAVE"
OUT=$(script -qec 'desktop-profile list' /dev/null 2>&1) || fail "list on empty store failed: $OUT"
echo "$OUT" | grep -q 'no encrypted profiles saved yet' || fail "empty list message wrong: $OUT"
OUT=$(script -qec 'desktop-profile status' /dev/null 2>&1) || fail "status on empty store failed: $OUT"
echo "$OUT" | grep -q 'Commits waiting to push' || fail "status died before the pending line: $OUT"
# and with the remote unreachable, status must still work (offline)
mv "$WORK/origin5.git" "$WORK/origin5.git.hidden"
OUT=$(script -qec 'desktop-profile status' /dev/null 2>&1) || fail "offline status failed: $OUT"
echo "$OUT" | grep -q 'Commits waiting to push' || fail "offline status died: $OUT"
mv "$WORK/origin5.git.hidden" "$WORK/origin5.git"
echo "   ok: empty and offline status work"

export PATH="$PATH_SAVE"; export DESKTOP_DATA_DIR="$DESKTOP_DATA_DIR_SAVE"

echo "PASS: backup/restore/profile safety (wrong password, corrupted + invalid + unsafe"
echo "      archives, mixed validity, confirmation, retention, personal-only and legacy"
echo "      profiles, failed push + retry, collision handling, pre-staged-file safety)"
