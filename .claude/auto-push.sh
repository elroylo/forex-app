#!/usr/bin/env bash
# Auto-commit & push the forex-app repo after each Claude Code session.
#
# Safety: this script is GUARDED so it can never act on the wrong repo.
# It only proceeds when the repo's `origin` remote is elroylo/forex-app,
# so even if it somehow runs from the home-directory repo it does nothing.

set -uo pipefail

# Locate the repo. CLAUDE_PROJECT_DIR is set by Claude Code for hooks and
# tracks the project root even if the SSD's drive letter changes. Fall back
# to the git toplevel of the current directory if it isn't set.
REPO="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$REPO" ] && exit 0

# --- SAFETY GUARD: only ever touch the forex-app repo ---
ORIGIN="$(git -C "$REPO" remote get-url origin 2>/dev/null)"
case "$ORIGIN" in
  *elroylo/forex-app*) ;;   # correct repo, continue
  *) exit 0 ;;              # anything else (incl. the home repo) -> do nothing
esac

# Nothing changed? Nothing to do.
if [ -z "$(git -C "$REPO" status --porcelain)" ]; then
  exit 0
fi

# Commit everything, then push the current branch.
git -C "$REPO" add -A
git -C "$REPO" commit -m "Auto-commit: $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1

if git -C "$REPO" push origin HEAD >/dev/null 2>&1; then
  SHA="$(git -C "$REPO" rev-parse --short HEAD)"
  printf '{"systemMessage":"Auto-pushed forex-app to GitHub (%s)"}\n' "$SHA"
else
  printf '{"systemMessage":"forex-app committed locally but push failed (offline?) - will push next session."}\n'
fi
