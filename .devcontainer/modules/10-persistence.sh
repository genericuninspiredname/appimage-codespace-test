#!/usr/bin/env bash
# 10-persistence.sh - persistent data dir, home symlinks, backup tool.
# Split from setup.sh (sections 1, 2, 3); behavior unchanged.
# Runs under the coordinator's "set -e". Uses: HOMEDIR DATA_DIR REMOTE_URL BIN_DIR.
# ---------------------------------------------------------------------------
# 1. Persistent data directory (survives stop/start and container rebuilds,
#    because /workspaces is preserved on rebuild; deleting the codespace
#    loses it unless backed up - see the backup script below).
#    Never overwrites anything already on disk: restore only fills a fresh
#    git repo, and merges (never replaces) existing folders.
# ---------------------------------------------------------------------------
if [ ! -d "$DATA_DIR/.git" ]; then
  git -C "$DATA_DIR" init -q -b desktop-data 2>/dev/null || { mkdir -p "$DATA_DIR" && git -C "$DATA_DIR" init -q -b desktop-data; }
  git -C "$DATA_DIR" remote remove origin >/dev/null 2>&1 || true
  git -C "$DATA_DIR" remote add origin "$REMOTE_URL"
  # Restore from GitHub if a previous backup exists. This makes the local
  # branch share the remote's history so future backups push cleanly.
  if git -C "$DATA_DIR" fetch -q origin desktop-data 2>/dev/null; then
    if git -C "$DATA_DIR" checkout -q -B desktop-data FETCH_HEAD 2>/dev/null; then
      git -C "$DATA_DIR" branch -q --set-upstream-to=origin/desktop-data desktop-data 2>/dev/null || true
    else
      echo "WARNING: could not restore backup cleanly (files already present?). Continuing without restore." >&2
    fi
  fi
fi
mkdir -p "$DATA_DIR/files" "$DATA_DIR/private"
git -C "$DATA_DIR" config user.name  >/dev/null 2>&1 || git -C "$DATA_DIR" config user.name "codespace"
git -C "$DATA_DIR" config user.email >/dev/null 2>&1 || git -C "$DATA_DIR" config user.email "codespace@users.noreply.github.com"

# Keep credentials/profiles and big binaries out of git (backup = documents only)
if [ ! -f "$DATA_DIR/.gitignore" ]; then
  cat > "$DATA_DIR/.gitignore" <<'IGN'
private/
*.mkv
*.mp4
*.avi
*.mov
*.webm
*.flv
*.wav
*.zip
*.tar.gz
*.7z
IGN
fi

# ---------------------------------------------------------------------------
# 2. Visible "Files" folder + persistent app settings (symlinked into $HOME,
#    which resets on rebuild; the data dir does not). Existing content is
#    always preserved: new files are merged in, existing files are kept.
# ---------------------------------------------------------------------------
link_dir() { # link_dir <src> <dest> [migrate]
  local src="$1" dest="$2" migrate="${3:-0}"
  [ -L "$src" ] && return 0                 # already linked
  mkdir -p "$(dirname "$src")" "$(dirname "$dest")"
  if [ -d "$dest" ]; then
    if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
      if [ "$migrate" = 1 ]; then
        # Whole-directory import for user documents: the entire source tree
        # (files, symlinks, empty folders - everything) is moved as-is into
        # the persistent destination, so no version can be lost. Only after
        # the move succeeds is the original path replaced by the symlink.
        local import_dir
        import_dir="$dest/Imported-from-home-$(date -u +%Y%m%d-%H%M%S)-$$"
        if ! mv "$src" "$import_dir" 2>/dev/null; then
          echo "WARNING: could not import $src into $dest; leaving it untouched" >&2
          return 0
        fi
      fi
      # For app configs (migrate=0) the persisted version wins; on rebuild
      # the source is only the fresh image default, so dropping it is safe.
    fi
    rm -rf "$src"
  elif [ -d "$src" ]; then
    mv "$src" "$dest"                        # first run: move existing in
  fi
  mkdir -p "$dest"
  ln -sfn "$dest" "$src"
}

link_dir "$HOMEDIR/Files"                     "$DATA_DIR/files" 1
link_dir "$HOMEDIR/.mozilla"                   "$DATA_DIR/private/mozilla"
# Roblox/Sober data (client downloads, login, settings) survives rebuilds
link_dir "$HOMEDIR/.var/app/org.vinegarhq.Sober"  "$DATA_DIR/private/sober"
link_dir "$HOMEDIR/.fluxbox"                  "$DATA_DIR/private/fluxbox"

# ---------------------------------------------------------------------------
# 3. Backup tool: explicitly backs up ~/Files (documents only, never
#    profiles/credentials) to the desktop-data branch of this repo.
#    Reinstalled on every setup run so fixes reach existing codespaces.
#    storage/backup-and-profile-safety: failed pushes now report how many
#    commits are waiting, a later run pushes them (and says so instead of
#    "already backed up"), and a diverged remote is explained instead of
#    being reported as a generic failure.
# ---------------------------------------------------------------------------
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/desktop-backup" <<'BK'
#!/usr/bin/env bash
set -e
DATA_DIR="${DESKTOP_DATA_DIR:-/workspaces/desktop-data}"
cd "$DATA_DIR"
git add -A -- files/ .gitignore
committed=0
if ! git diff --cached --quiet; then
  git commit -qm "backup $(date -u +%Y-%m-%d_%H:%M)"
  committed=1
fi
# Fetch first: the pending-commit count below compares against the remote.
git fetch -q origin desktop-data 2>/dev/null || true
pending() { # commits on desktop-data that GitHub does not have yet
  git rev-list --count FETCH_HEAD..HEAD 2>/dev/null \
    || git rev-list --count --all --not --remotes 2>/dev/null || echo 0
}
PENDING=$(pending)
# Always attempt the push: retries after earlier failures, even with no
# new changes, so locally-committed backups reach GitHub eventually.
# No automatic rebase/merge: a diverged remote is reported as a failure so
# documents are never rewritten with conflict markers.
if git push -q -u origin desktop-data 2>/tmp/desktop-push.err; then
  if [ "$committed" = 1 ]; then
    echo "Backed up to GitHub (branch: desktop-data)."
  elif [ "$PENDING" -gt 0 ] 2>/dev/null; then
    echo "Pushed $PENDING pending backup commit(s) that an earlier run failed to upload."
  else
    echo "Everything already backed up."
  fi
else
  echo "Push to GitHub FAILED:" >&2
  head -3 /tmp/desktop-push.err >&2
  echo "Your changes are saved locally ($PENDING commit(s) waiting to push)" >&2
  echo "- run this again later to retry." >&2
  # The one failure a plain retry cannot fix: someone else pushed backups
  # (another codespace) and the remote has commits this codespace lacks.
  if git rev-parse -q --verify FETCH_HEAD >/dev/null 2>&1 \
     && ! git merge-base --is-ancestor FETCH_HEAD HEAD; then
    echo "The desktop-data branch on GitHub has commits this codespace lacks" >&2
    echo "(backed up from another codespace?). Inspect and resolve manually:" >&2
    echo "  git -C $DATA_DIR log --oneline FETCH_HEAD..HEAD    # your local backups" >&2
    echo "  git -C $DATA_DIR pull --rebase origin desktop-data  # then run this again" >&2
  fi
  exit 1
fi
BK
chmod +x "$BIN_DIR/desktop-backup"
