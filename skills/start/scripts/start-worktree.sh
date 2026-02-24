#!/usr/bin/env bash
set -euo pipefail

BRANCH_NAME="$1"
STATE_JSON="$2"
MAIN_REPO="$(git rev-parse --show-toplevel)"
DIR_NAME="${BRANCH_NAME//\//-}"

# Read worktree directory from state JSON, default to .worktrees
WORKTREE_DIR=$(echo "${STATE_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('worktreePath','').rsplit('/',1)[0])" 2>/dev/null || echo "${MAIN_REPO}/.worktrees")
WORKTREE_PATH="${WORKTREE_DIR}/${DIR_NAME}"

# Read base branch from config or default to main
BASE_BRANCH=$(python3 -c "
import json, os
config_path = os.path.join('${MAIN_REPO}', '.claude', 'session-config.json')
try:
    config = json.load(open(config_path))
    print(config.get('github', {}).get('baseBranch', 'main'))
except:
    print('main')
" 2>/dev/null || echo "main")

git fetch origin "${BASE_BRANCH}"
git worktree add "${WORKTREE_PATH}" -b "${BRANCH_NAME}" "origin/${BASE_BRANCH}"

mkdir -p "${WORKTREE_PATH}/.claude"
echo "${STATE_JSON}" | python3 -m json.tool > "${WORKTREE_PATH}/.claude/session-state.json"

mkdir -p "${MAIN_REPO}/.claude/worktree-sessions"
echo "${STATE_JSON}" | python3 -m json.tool > "${MAIN_REPO}/.claude/worktree-sessions/${DIR_NAME}.json"

echo "${WORKTREE_PATH}"
