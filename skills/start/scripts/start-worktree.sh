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

# Copy .claude/settings.json if it exists (needed as base for deny rules)
[ -f "${MAIN_REPO}/.claude/settings.json" ] && cp "${MAIN_REPO}/.claude/settings.json" "${WORKTREE_PATH}/.claude/settings.json"

# Add Supabase MCP deny rules to worktree settings (prevent production mutations)
python3 -c "
import json, os
settings_path = '${WORKTREE_PATH}/.claude/settings.json'
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)

perms = settings.setdefault('permissions', {})
deny = set(perms.get('deny', []))

# Block all mutating Supabase MCP tools in worktree sessions
# DB changes must be done via migration files, not MCP
deny.update([
    'mcp__claude_ai_Supabase__apply_migration',
    'mcp__claude_ai_Supabase__deploy_edge_function',
    'mcp__claude_ai_Supabase__create_branch',
    'mcp__claude_ai_Supabase__delete_branch',
    'mcp__claude_ai_Supabase__merge_branch',
    'mcp__claude_ai_Supabase__reset_branch',
    'mcp__claude_ai_Supabase__rebase_branch',
    'mcp__claude_ai_Supabase__create_project',
    'mcp__claude_ai_Supabase__pause_project',
    'mcp__claude_ai_Supabase__restore_project',
])

perms['deny'] = sorted(deny)
settings['permissions'] = perms
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" 2>/dev/null || true

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

# Create worktree-specific instructions (Claude Code bug workaround)
# See: https://github.com/anthropics/claude-code/issues/8771
cat > "${WORKTREE_PATH}/CLAUDE.local.md" << 'LOCALEOF'
# Worktree Session Rules

## Path Safety
This is a git worktree, NOT the main repository.
ALL file paths are relative to THIS directory (the current working directory from `<env>`).
- Use `./` prefix for all file operations
- NEVER resolve paths to the parent repository
- `supabase/` means `./supabase/` in THIS directory

## Supabase: Migration Files Only
Supabase preview branches are created when the PR is opened (by `/done`).
During this session, the preview branch does NOT exist yet.

**Rules:**
- All database schema changes MUST be written as `.sql` migration files in `./supabase/migrations/`
- Supabase MCP mutating tools are BLOCKED (apply_migration, deploy_edge_function, create/delete/merge/reset/rebase_branch)
- Supabase MCP read-only tools are allowed (list_tables, list_migrations, execute_sql with SELECT, get_logs, search_docs)
- `execute_sql` may ONLY be used for SELECT queries — never INSERT, UPDATE, DELETE, CREATE, ALTER, DROP

**Workflow:** Write migration → `/done` creates PR → Supabase auto-creates preview branch → migrations run on preview
LOCALEOF

echo "${WORKTREE_PATH}"
