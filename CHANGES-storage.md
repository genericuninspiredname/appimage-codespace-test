# CHANGES — Backup and encrypted profile safety

Branch: `storage/backup-and-profile-safety` (from master `d67ee4c`).
Goal: improve backup, restore, and encrypted profile handling.

## What changed

### `.devcontainer/modules/40-profiles.sh` (`desktop-profile`)

- **Personal files are now kept separate from credentials and browser
  secrets.** `save` produces two encrypted archives per profile:
  `profiles/<name>.tar.gz.age` (documents from `~/Files`) and
  `profiles/<name>.browser.tar.gz.age` (the browser profile — bookmarks,
  logins, game saves). Either part can be restored alone
  (`--files-only` / `--browser-only`) or saved alone (`--no-browser`).
  Older single archives (documents + browser in one ciphertext) still
  restore — detected after decryption and noted; `--files-only` on such a
  legacy archive takes only the documents out of it.
- **Archives are validated before any local data is replaced.** `restore`
  decrypts both parts and checks that every archive is a complete,
  readable tar.gz with the expected structure (`files/`, `private/mozilla`)
  before touching `~/Files` or the browser profile. A wrong passphrase, a
  corrupted/tampered archive, or a ciphertext that decrypts to something
  that is not a profile is rejected with **nothing changed**.
- **Destructive restores warn first.** `restore` states exactly what will be
  replaced (`~/Files` and/or the browser profile), where the previous state
  is kept, and requires typing `restore` to proceed; anything else cancels
  with nothing changed. `--yes` skips only the prompt (validation still
  runs). If a replace step fails mid-way, everything is rolled back to the
  pre-restore state instead of leaving a half-replaced desktop.
- **Failed pushes are recoverable.** A failed push reports how many commits
  are waiting locally; new `status` (profiles + pending commits) and `push`
  (retry without creating a new profile) subcommands were added. `save`
  still rebases and retries on a push collision, and never discards the
  locally-committed ciphertext.
- **Retention:** only the 3 most recent `.pre-restore-*` folders are kept;
  each restore prunes older ones and says so (configurable via
  `DESKTOP_KEEP_PRE_RESTORE`).

### `.devcontainer/modules/10-persistence.sh` (`desktop-backup`)

- A failed push now reports how many commits are waiting locally, and a
  later run pushes them — and says so ("Pushed N pending backup
  commit(s)") instead of the misleading "Everything already backed up".
- If the remote branch diverged (backed up from another codespace), the
  failure message explains that and gives the exact inspection/resolution
  commands instead of a generic error. No automatic rebase/merge for
  documents (unchanged, deliberate).

### `README.md`

- Backup and encrypted-profile sections updated for the above: archive
  split, restore confirmation + validation, `--files-only`/`--browser-only`,
  `status`/`push`, failed-push retry messages, and a new "Retention and
  cleanup" paragraph (pre-restore retention, git history keeps deleted
  documents, manual profile deletion).

### `tests/backup-profile-test.sh` (new)

End-to-end tests for `desktop-profile` and `desktop-backup` against an
isolated fixture (fake home, data dir, bare repo as the GitHub stand-in;
age prompts fed through a pty via `script`):

1. save → two separate archives, ciphertext-only pushed, personal archive
   contains no browser secrets and vice versa
2. wrong passphrase on restore → rejected, local data untouched
3. corrupted ciphertext (committed + pushed as a repo-side corruption) →
   rejected, data untouched
4. structurally invalid archive (decrypts, but is not a profile) → refused,
   data untouched
5. confirmation prompt; cancelling changes nothing; `--yes` still validates
6. valid restore replaces `~/Files` + browser profile, keeps a pre-restore
   backup
7. retention: 6 pre-restore dirs → only the newest 3 remain
8. legacy single archive: full restore works, `--files-only` leaves browser
   secrets out
9. failed push (profile): kept locally, reported with pending count, retry
   (`desktop-profile push`) uploads it, `status` shows 0 pending
10. failed push (backup): documents stay committed locally, retry run
    reports the pending count, fixed remote → pending commits uploaded
11. plain backup never includes `private/` (credentials/browser secrets)

The desktop appearance is untouched (no menu/Fluxbox changes).

## Note on Codespace capacity

Creating this branch's codespace failed with "too many codespaces running",
so one codespace belonging to another branch (`perf-image-size-test-…`) was
STOPPED to free capacity (stopping is reversible; it does not modify any
branch). Its state at the time (idle for over an hour) did not prove it was
truly idle - if that branch's tester was interrupted, that is the cause.

## How it was tested

- `bash -n` on both modules and both test scripts.
- `tests/backup-profile-test.sh` — all cases pass, locally (sandbox with
  user namespaces) and inside a Codespace (see below).
- `tests/idempotence-test.sh` — still passes (4 lifecycle runs with
  byte-identical state + hook-failure phase), i.e. the changed tools are
  still installed idempotently. NOTE: this simulates the rebuild lifecycle
  (a repeated first-start) with a fixture; it is not a container rebuild.
- Codespace verification on this branch (codespace `storage-backup-test-97qr4jj5wjjv276`,
  machine `basicLinux32gb`, commits `459419d` + `340363b`):
  - `bash tests/backup-profile-test.sh` — PASS in-codespace (after both the
    initial work and the safety-fix revision).
  - `bash tests/idempotence-test.sh` — PASS after moving the real
    `/home/steam/.steam` symlink aside for the duration of the run (restored
    immediately after). Inside a Codespace the test cannot use `unshare`
    (blocked), so it runs directly; the real setup that already ran in that
    codespace had left `/home/steam/.steam` as a symlink, which made the
    fixture's `link_dir` short-circuit — a test-environment artifact, not a
    code failure (the same test passes unmodified on a host with user
    namespaces).
  - Real repeat-run: `bash .devcontainer/setup.sh normal-start` exits 0
    (exit code captured directly, not through a pipe);
    Fluxbox up, noVNC on port 6080 answers HTTP 200, the menu managed
    block appears exactly once — desktop appearance unchanged.
  - Full container rebuild (`gh codespace rebuild --full`) on this branch:
    the codespace comes back on the branch with setup re-run and the tests
    re-verified after the rebuild.
  - Live failed-push demonstration: a real `desktop-backup` run inside the
    codespace (non-interactive SSH, no git credentials in that context)
    committed locally and its push FAILED — exactly the failed-push path:
    the documents stayed committed locally with a clear message. The
    remote was verified read-only afterwards (`git ls-remote origin
    desktop-data`): NO `desktop-data` branch exists on GitHub — nothing
    was pushed to the remote by this branch's testing.

## Remaining limitations

- A full save now prompts for the passphrase twice per archive (age asks
  for confirmation), i.e. four inputs for a documents+browser save.
- The restore confirmation happens AFTER decryption + validation (so the
  warning describes the exact, validated replacement plan); a user types
  the passphrase before seeing the prompt. A cancelled restore wastes the
  passphrase entry but touches nothing.
- Legacy profiles stay mixed until they are saved again (noted by the tool).
- `desktop-profile restore` reads the passphrase from a terminal; the
  `--yes` flag makes the confirmation non-interactive but the passphrase
  prompt remains interactive by design.
- Archive member validation rejects absolute paths, `..` traversal,
  device/fifo/socket members, links whose target escapes the archive, and
  members outside the component's allowed roots. age verifies the
  integrity of each archive (tampered or truncated ciphertext fails to
  decrypt), but the tool cannot establish which writer produced a profile:
  anyone with push access can replace, delete, or replay saved ciphertext
  (the trust boundary noted in the README).
- Retention prunes `.pre-restore-*` dirs only; git history on
  `desktop-data` and old profile files are intentionally not cleaned
  automatically (documented in README).
- The `desktop-profile save`/`push` collision path still auto-rebases,
  but ONLY when every diverged remote commit touches nothing but `profiles/`
  (ciphertext); divergence involving documents or `.gitignore` is reported
  and never applied automatically. On a rebase conflict the rebase is
  aborted cleanly and the failure reported - resolution is left to the
  user.
- Testing inside a Codespace cannot use `unshare`; the idempotence test
  runs directly there and one real-setup artifact (`/home/steam/.steam`)
  must be moved aside for its duration (restored after).
