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

# Copy gitignored config files that worktrees need
[ -f "${MAIN_REPO}/.claude/session-config.json" ] && cp "${MAIN_REPO}/.claude/session-config.json" "${WORKTREE_PATH}/.claude/session-config.json"
[ -f "${MAIN_REPO}/.entire/settings.json" ] && mkdir -p "${WORKTREE_PATH}/.entire" && cp "${MAIN_REPO}/.entire/settings.json" "${WORKTREE_PATH}/.entire/settings.json"

mkdir -p "${MAIN_REPO}/.claude/worktree-sessions"
echo "${STATE_JSON}" | python3 -m json.tool > "${MAIN_REPO}/.claude/worktree-sessions/${DIR_NAME}.json"


# Copy skills installation to worktree (not in git, created by npx skills add)
if [ -d "${MAIN_REPO}/.agents/skills" ]; then
  cp -R "${MAIN_REPO}/.agents" "${WORKTREE_PATH}/.agents"
  mkdir -p "${WORKTREE_PATH}/.claude/skills"
  for skill_dir in "${MAIN_REPO}/.claude/skills"/*; do
    [ -e "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    ln -sf "../../.agents/skills/${skill_name}" "${WORKTREE_PATH}/.claude/skills/${skill_name}"
  done
fi

# Create worktree-specific path safety instructions (Claude Code bug workaround)
# See: https://github.com/anthropics/claude-code/issues/8771
cat > "${WORKTREE_PATH}/CLAUDE.local.md" << 'LOCALEOF'
# Worktree Path Safety

**This is a git worktree, NOT the main repository.**

ALL file paths are relative to THIS directory (the current working directory from `<env>`).
NEVER resolve paths to the parent repository at the main repo location.

When creating or editing files:
- Use `./` prefix: `./supabase/migrations/`, `./apps/web/`, `./packages/`
- Verify with `pwd` before writing if unsure
- The `supabase/` directory means `./supabase/` in THIS worktree directory

Session state is in `.claude/session-state.json` in this directory.
LOCALEOF

echo "${WORKTREE_PATH}"
