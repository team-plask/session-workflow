---
name: start
description: Start a task session — creates a Linear issue, git worktree, and launches a new Claude session. Use when the user says /start or wants to begin a new isolated task.
user-invocable: true
allowed-tools: Bash(git:*) Bash(osascript:*) Bash(bash:*) mcp__linear-server__create_issue mcp__claude_ai_Linear__create_issue
---

# Start Task Session

Create a Linear issue, git worktree, and launch a new Claude session for the task.

**Task:** $ARGUMENTS

## Instructions

### Step 0: Load Config

Read `.claude/session-config.json` from the project root. If it doesn't exist, use these defaults:

```json
{
  "linear": { "team": "Engineering", "labels": ["claude-session"], "startState": "started" },
  "github": { "baseBranch": "main" },
  "supabase": { "directory": "", "branchingEnabled": false },
  "entire": { "enabled": false },
  "worktrees": { "directory": ".worktrees" }
}
```

Use config values throughout (referred to as `config.linear.team`, etc.).

### Step 1: Clean Up Previous Worktrees

Run the cleanup script to remove any completed worktrees from previous sessions:

```bash
bash "$(dirname "$(claude skill path start")")/scripts/done-cleanup.sh" 2>/dev/null || true
```

If the skill script path isn't resolvable, fall back to:
```bash
# Find the done-cleanup.sh in .claude/skills
find .claude/skills -name "done-cleanup.sh" -exec bash {} \; 2>/dev/null || true
```

### Step 2: Create Linear Issue

Use the Linear MCP tool (try `mcp__linear-server__create_issue` first, fall back to `mcp__claude_ai_Linear__create_issue`) to create a new issue:

- **team**: `config.linear.team`
- **title**: Derive a short, descriptive title from `$ARGUMENTS` (e.g., "Fix login bug on reservation form")
- **labels**: `config.linear.labels`
- **state**: `config.linear.startState`
- **assignee**: "me"

From the response, extract:
- `id` (UUID)
- `identifier` (e.g., "LNY-350")
- `gitBranchName` (e.g., "junho/lny-350-fix-login-bug")
- `url` (e.g., "https://linear.app/.../LNY-350")

### Step 3: Create Worktree

Build the state JSON object:

```json
{
  "linearIssueId": "<id from step 2>",
  "linearIssueIdentifier": "<identifier from step 2>",
  "linearIssueUrl": "<url from step 2>",
  "linearBranchName": "<gitBranchName from step 2>",
  "worktreePath": "<repo-root>/<config.worktrees.directory>/<sanitized-branch>",
  "mainRepoPath": "<repo-root>",
  "taskDescription": "$ARGUMENTS",
  "createdAt": "<current ISO timestamp>",
  "status": "active"
}
```

Where `<sanitized-branch>` is the `gitBranchName` with `/` replaced by `-`.

Run the worktree creation script:

```bash
# Find the start-worktree.sh script
SCRIPT=$(find .claude/skills -name "start-worktree.sh" | head -1)
bash "$SCRIPT" "<gitBranchName>" '<state-json>'
```

The script will:
- Create the worktree directory with a new branch from `origin/<baseBranch>`
- Write `.claude/session-state.json` inside the worktree
- Write `.claude/worktree-sessions/<sanitized-branch>.json` in the main repo

### Step 4: Launch Claude in Worktree

Open a new Terminal tab with Claude running in the worktree:

```bash
osascript -e 'tell application "Terminal" to do script "cd <worktree-path> && claude"'
```

Replace `<worktree-path>` with the actual worktree path returned from Step 3.

### Step 5: Confirm

Print a summary:

```
Linear: <identifier> - <url>
Branch: <gitBranchName>
Worktree: <worktrees-dir>/<sanitized-branch>/
New Terminal tab opened with Claude session
```

Tell the user to switch to the new Terminal tab to start working.
