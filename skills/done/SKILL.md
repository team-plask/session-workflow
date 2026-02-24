---
name: done
description: Wrap up the current session — commits, pushes, creates PR, updates Linear. Detects worktree vs main branch context automatically.
user-invocable: true
allowed-tools: Bash(git:*) Bash(gh:*) Bash(entire:*) mcp__linear-server__create_comment mcp__linear-server__update_issue mcp__linear-server__create_issue mcp__claude_ai_Linear__create_comment mcp__claude_ai_Linear__update_issue mcp__claude_ai_Linear__create_issue
---

# Session Wrap-up

Wrap up the current session. Behavior depends on whether you're in a worktree or on main.

## Instructions

### Step 0: Load Config & Detect Context

Read `.claude/session-config.json` from the project root. If it doesn't exist, use defaults:

```json
{
  "linear": { "team": "Engineering", "labels": ["claude-session"], "doneState": "done" },
  "github": { "baseBranch": "main" },
  "supabase": { "directory": "", "branchingEnabled": false },
  "entire": { "enabled": false },
  "worktrees": { "directory": ".worktrees" }
}
```

Detect context:

```bash
git branch --show-current
```

Read `.claude/session-state.json` if it exists.

**Worktree path**: branch is NOT `config.github.baseBranch` AND `session-state.json` contains `linearIssueId` and `linearBranchName`
**Main path**: branch IS `config.github.baseBranch` OR no valid session-state

---

## Worktree Path (branch with Linear issue)

### Step 1: Gather Changes

Run these to understand what was done:

```bash
git diff <baseBranch> --stat
git log <baseBranch>..HEAD --oneline
```

If `config.entire.enabled`:
```bash
entire explain --short 2>&1 || true
```

Build a concise summary of changes from conversation history + the above output.

### Step 2: Detect Supabase Changes

If `config.supabase.branchingEnabled` and `config.supabase.directory` is set, check for Supabase file changes:

```bash
git diff <baseBranch> --name-only -- <config.supabase.directory>
```

If there are changed files, set `hasSupabaseChanges = true` and collect the changed files list.

### Step 3: Commit (if needed)

Check for uncommitted changes:

```bash
git status --porcelain
```

If there are uncommitted changes, ask the user if they want to commit. If yes, stage and commit with a descriptive message.

### Step 4: Push Branch

```bash
git push -u origin <branch-name>
```

Use the branch name from `git branch --show-current`.

### Step 5: Create Pull Request

Build the PR body. Start with the standard summary, then conditionally add sections:

**Standard sections:**
- Summary of changes
- Key decisions made
- Files modified (grouped by purpose)

**If `hasSupabaseChanges`:**
Add a "Database Changes" section:
```markdown
## Database Changes

This PR includes Supabase schema changes that will trigger a preview branch:

<list of changed files from Step 2>

The Supabase GitHub integration will automatically create a preview database branch for this PR.
```

Create the PR:

```bash
gh pr create --title "<identifier>: <short-title>" --body "<summary>" --base <baseBranch>
```

If `hasSupabaseChanges`, also add the `supabase` label:
```bash
gh pr edit --add-label "supabase" 2>/dev/null || true
```

### Step 6: Update Linear

Use Linear MCP tools (try `mcp__linear-server__*` first, fall back to `mcp__claude_ai_Linear__*`).

Add a comment on the Linear issue (`linearIssueId` from session-state) with:
- PR URL
- Summary of changes
- If supabase changes: note about preview database branch

Then update the issue state to `config.linear.doneState`.

### Step 7: Mark for Cleanup

Read the worktree session file from the main repo:
`<mainRepoPath>/.claude/worktree-sessions/<sanitized-branch>.json`

Update the file: set `"status": "done"`.
Also update the local `.claude/session-state.json` with `"status": "done"`.

### Step 8: Confirm

Print:
- PR URL
- Linear issue identifier + "Done" status
- If supabase changes: "Supabase preview branch will be created automatically"
- Tell the user: "Close this terminal tab."

---

## Main Path (fallback — no worktree)

### Step 1: Gather Minimal Context

Run:

```bash
git branch --show-current
```

If `config.entire.enabled`:
```bash
entire status 2>&1
```

Extract the current session ID from entire status output, then:

```bash
entire explain --session <session_id> --short 2>&1
```

Check for linked Linear issue in `.claude/session-state.json`.

### Step 2: Assess Work Type

Based on conversation history and checkpoint summary, classify:

| Type | Examples | Needs git diff? |
|------|----------|----------------|
| **code** | Feature, bugfix, refactor | Yes |
| **config** | Supabase dashboard, Linear setup | No |
| **research** | Investigation, planning | No |
| **ops** | Deploy, server config | No |

Only run `git diff --stat` if type is **code** or files were changed.

### Step 3: Build Summary

Write a concise summary with only relevant sections:

- **Summary** — what was accomplished (always)
- **Key Decisions** — only if architectural/design decisions were made
- **Files Changed** — only if files were changed, grouped by purpose
- **Follow-ups** — only if there are open items
- **Metadata** — session ID, branch, date (always)

### Step 4: Push to Linear

Use Linear MCP tools. Team is `config.linear.team`.

**If session-state has `linearIssueId`:**
- Add a comment to the existing issue

**If no linked issue:**
- Create a new issue:
  - **team**: `config.linear.team`
  - **title**: Short, descriptive (e.g., "Session: Configure Supabase branching")
  - **labels**: `config.linear.labels`
  - **description**: The summary from Step 3

### Step 5: Save State

Write `.claude/session-state.json`:

```json
{
  "linearIssueId": "<the issue ID>",
  "linearIssueIdentifier": "<e.g. LNY-123>",
  "sessionId": "<entire session ID>",
  "branch": "<branch name>",
  "lastUpdated": "<ISO timestamp>"
}
```

### Step 6: Confirm

Tell the user:
- Linear issue identifier and URL
- One-line summary of what was tracked
