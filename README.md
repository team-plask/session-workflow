# Session Workflow

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that provides `/start` and `/done` commands for structured task sessions with Linear issue tracking, git worktrees, GitHub PRs, and optional Supabase branching.

## What it does

### `/start <task description>`

1. Cleans up completed worktrees from previous sessions
2. Creates a Linear issue with your task description
3. Creates an isolated git worktree with a new branch
4. Opens a new Terminal tab with Claude running in the worktree

### `/done`

**In a worktree** (branch with Linear issue):
1. Gathers and summarizes all changes
2. Detects Supabase schema changes via `git diff` (adds "Database Changes" section to PR)
3. Commits uncommitted work (with your approval)
4. Pushes the branch and creates a GitHub PR
5. Updates the Linear issue with PR link and summary
6. Marks the worktree for cleanup

**On main** (fallback):
1. Summarizes the session from conversation history
2. Creates or updates a Linear issue with the summary

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated
- [Linear MCP server](https://github.com/linear/linear-mcp) configured in Claude Code
- Git configured with push access to your repository

### Optional

- [Supabase GitHub integration](https://supabase.com/docs/guides/platform/branching) for automatic preview branches on PRs with database changes
- [Entire](https://entire.dev) CLI for session checkpoints

## Installation

```bash
npx skills add team-plask/session-workflow
```

## Configuration

Create `.claude/session-config.json` in your project root:

```json
{
  "linear": {
    "team": "Engineering",
    "labels": ["claude-session"],
    "startState": "started",
    "doneState": "done"
  },
  "github": {
    "baseBranch": "main"
  },
  "supabase": {
    "directory": "",
    "branchingEnabled": false
  },
  "entire": {
    "enabled": false
  },
  "worktrees": {
    "directory": ".worktrees"
  }
}
```

### Configuration Options

| Key | Description | Default |
|-----|-------------|---------|
| `linear.team` | Your Linear team name | `"Engineering"` |
| `linear.labels` | Labels to apply to created issues | `["claude-session"]` |
| `linear.startState` | Issue state when starting a task | `"started"` |
| `linear.doneState` | Issue state when completing a task | `"done"` |
| `github.baseBranch` | Base branch for worktrees and PRs | `"main"` |
| `supabase.directory` | Path to Supabase directory (relative to repo root) | `""` |
| `supabase.branchingEnabled` | Enable Supabase change detection in `/done` | `false` |
| `entire.enabled` | Enable Entire CLI integration | `false` |
| `worktrees.directory` | Directory for git worktrees | `".worktrees"` |

Add to `.gitignore`:
```
.claude/session-config.json
```

## Optional Setup

### Supabase Branching

If your project uses Supabase, enable the [GitHub integration](https://supabase.com/dashboard/project/_/settings/integrations) for automatic preview database branches:

1. Go to your Supabase project → Settings → Integrations
2. Connect GitHub and select your repository
3. Set the Supabase directory (e.g., `apps/web/supabase`)
4. Enable "Automatic branching" with "Supabase changes only"

Then set in your config:
```json
{
  "supabase": {
    "directory": "apps/web/supabase",
    "branchingEnabled": true
  }
}
```

When `/done` creates a PR, it checks `git diff` for changes in the configured Supabase directory. If changes are found, it adds a "Database Changes" section to the PR body and applies a `supabase` label so the Supabase GitHub integration can create a preview branch automatically.

### Entire Integration

If you use [Entire](https://entire.dev) for session checkpoints:

```json
{
  "entire": {
    "enabled": true
  }
}
```

### Auto-cleanup Hook

Add a SessionStart hook to `.claude/settings.json` for automatic worktree cleanup:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "find .claude/skills -name 'done-cleanup.sh' -exec bash {} \; 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

## Usage

### Starting a task

```
/start Fix the login bug on the reservation form
```

This creates:
- Linear issue: `ENG-123 - Fix login bug on reservation form`
- Branch: `user/eng-123-fix-login-bug`
- Worktree: `.worktrees/user-eng-123-fix-login-bug/`
- New Terminal tab with Claude session

### Completing a task

In the worktree terminal:

```
/done
```

This creates:
- Git commit (if uncommitted changes, with approval)
- GitHub PR: `ENG-123: Fix login bug on reservation form`
- Linear comment with PR link and summary
- Linear issue moved to "done"

## How It Works

### Worktree Architecture

Each `/start` creates an isolated git worktree — a separate working directory with its own branch, sharing the same `.git` directory. This lets you:

- Work on multiple tasks simultaneously without stashing
- Keep the main branch clean while tasks are in progress
- Easily switch between tasks by switching Terminal tabs

### State Management

- `.claude/session-state.json` — Written in each worktree, tracks the current session
- `.claude/worktree-sessions/<branch>.json` — Written in the main repo, tracks all active worktrees
- When `/done` runs, it marks the session as "done" so the cleanup script can remove the worktree

### Cleanup

Completed worktrees are cleaned up automatically on the next `/start` or session start (via hook). The cleanup script:
1. Scans `.claude/worktree-sessions/` for sessions with `"status": "done"`
2. Removes the corresponding worktree via `git worktree remove`
3. Prunes orphaned worktree references
4. Deletes the session tracking file

## License

MIT
