#!/usr/bin/env bash
set -euo pipefail

MAIN_REPO="$(git rev-parse --show-toplevel)"
SESSIONS_DIR="${MAIN_REPO}/.claude/worktree-sessions"
[ -d "$SESSIONS_DIR" ] || exit 0

for f in "$SESSIONS_DIR"/*.json; do
  [ -f "$f" ] || continue
  STATUS=$(python3 -c "import json; print(json.load(open('$f')).get('status','active'))" 2>/dev/null || echo "active")
  if [ "$STATUS" = "done" ]; then
    DIR_NAME=$(basename "$f" .json)
    # Read worktree directory from config or default to .worktrees
    WORKTREE_DIR=$(python3 -c "
import json, os
config_path = os.path.join('${MAIN_REPO}', '.claude', 'session-config.json')
try:
    config = json.load(open(config_path))
    print(config.get('worktrees', {}).get('directory', '.worktrees'))
except:
    print('.worktrees')
" 2>/dev/null || echo ".worktrees")
    WORKTREE="${MAIN_REPO}/${WORKTREE_DIR}/${DIR_NAME}"
    [ -d "$WORKTREE" ] && git worktree remove "$WORKTREE" --force 2>/dev/null || true
    git worktree prune 2>/dev/null || true
    rm -f "$f"
  fi
done
