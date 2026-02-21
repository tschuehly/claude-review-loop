# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Claude Code plugin with two workflows:
1. **Review Loop** — Claude implements a task, Codex independently reviews the changes, then Claude addresses the review feedback.
2. **Ralph Loop** — Claude creates a structured plan, Codex reviews it, Claude refines it, then an external script iterates through each step with implement/review/address cycles.

Distributed via the Claude Code plugin marketplace.

## Architecture

This is a **pure shell/markdown plugin** — no package.json, no compiled assets, no npm dependencies.

### Key Components

**Review Loop:**
- **`plugins/review-loop/hooks/stop-hook.sh`** — Review loop lifecycle engine. Intercepts Claude's exit via the Stop hook mechanism to run Codex reviews and manage the state machine (`task` → `addressing` → `approve`).
- **`plugins/review-loop/commands/review-loop.md`** — Slash command `/review-loop`. Contains inline bash that creates the state file and initializes the loop.
- **`plugins/review-loop/commands/cancel-review.md`** — Slash command `/cancel-review`.
- **`plugins/review-loop/commands/review.md`** — Slash command `/review` for on-demand Codex reviews.
- **`plugins/review-loop/scripts/setup-review-loop.sh`** — Standalone setup script with argument parsing, dependency checks, and state initialization.

**Ralph Loop:**
- **`plugins/review-loop/hooks/ralph-stop-hook.sh`** — Ralph loop lifecycle engine. Manages the plan review state machine (`ralph-plan` → `ralph-addressing` → `approve`).
- **`plugins/review-loop/commands/ralph-plan.md`** — Slash command `/ralph-plan`. Creates state file and instructs Claude to write `plan.md`.
- **`plugins/review-loop/commands/ralph-cancel.md`** — Slash command `/ralph-cancel`.
- **`plugins/review-loop/scripts/ralph-loop.sh`** — External implementation script. Iterates through `plan.md` steps using `claude -p` and `codex`.

**Shared:**
- **`plugins/review-loop/hooks/hooks.json`** — Registers both stop hooks with a 900s (15 min) timeout.
- **`plugins/review-loop/.claude-plugin/plugin.json`** — Plugin manifest. **Single source of truth for version.**
- **`.claude-plugin/marketplace.json`** — Marketplace distribution metadata (no version field — defers to plugin.json).
- **`plugins/review-loop/AGENTS.md`** — Agent operating guidelines (CLAUDE.md in that directory is a symlink to it).

### State Machines

Each workflow has its own state file, stop hook, and log file:

**Review Loop:**
- State: `.claude/review-loop.local.md` (gitignored)
- Log: `.claude/review-loop.log`
- Phases: `task` → `addressing` → exit
- Review artifacts: `reviews/review-<id>.md`

**Ralph Loop:**
- State: `.claude/ralph-loop.local.md` (gitignored)
- Log: `.claude/ralph-loop.log`
- Phases: `ralph-plan` → `ralph-addressing` → exit
- Review artifacts: `reviews/plan-review-<id>.md` (plan phase), `reviews/ralph-review-<id>.md` (implementation steps)
- Plan: `plan.md` (project artifact, NOT gitignored)
- Progress: `progress.txt` (gitignored, ephemeral tracking)

### plan.md Format

```markdown
# Plan: <descriptive title>

## Phase 1: <phase name>
- [ ] Step 1.1: <step title>
  Description: <what to do>
  Files: <files to create or modify>
  Acceptance: <how to verify this step is done>
```

Steps are checked off (`- [x]`) by `ralph-loop.sh` (the script is source of truth, not Claude). `progress.txt` is updated by Claude to provide context for subsequent iterations.

## Critical Conventions

- **Shell scripts must work on both macOS and Linux** — handle `sed -i ''` (macOS) vs `sed -i` (Linux) differences.
- **Stop hooks MUST always produce valid JSON to stdout** — never let non-JSON text leak. All logging goes to respective log files, Codex stdout/stderr is redirected away from hook stdout.
- **Fail-open on errors** — on any error, approve exit rather than trapping the user in a broken loop. The ERR trap in both stop hooks enforces this.
- **Review ID validation** — IDs are validated against `^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$` before path construction to prevent path traversal.
- **Version management** — `plugin.json` is the single source of truth for version. `marketplace.json` intentionally omits version.
- **Workflow isolation** — Review loop and Ralph loop use separate state files, stop hooks, and log files. They can coexist without interference.

## Testing

After modifying `stop-hook.sh`, test all three paths:

1. **No state file** — no loop active, should output `{"decision":"approve"}`
2. **task → addressing** — runs Codex review, transitions phase, blocks exit
3. **addressing → approve** — allows exit, cleans up state file

After modifying `ralph-stop-hook.sh`, test all three paths:

1. **No state file** — no loop active, should output `{"decision":"approve"}`
2. **ralph-plan → ralph-addressing** — runs Codex plan review, transitions phase, blocks exit
3. **ralph-addressing → approve** — allows exit, cleans up state file

Verify JSON output validity for each path:
```bash
echo '{}' | bash plugins/review-loop/hooks/stop-hook.sh | jq .
echo '{}' | bash plugins/review-loop/hooks/ralph-stop-hook.sh | jq .
```

Also test:
- Codex unavailable (should fall back to self-review prompt)
- Malformed state files (should fail-open)
- `ralph-loop.sh` with a simple 2-step plan.md

## Dependencies

- **Required:** `jq` for JSON processing in the stop hooks
- **Optional:** `codex` CLI for independent reviews (gracefully falls back to Claude self-review)
- **Optional:** `claude` CLI for `ralph-loop.sh` (uses `claude -p` for non-interactive implementation)

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `REVIEW_LOOP_CODEX_FLAGS` | `--dangerously-bypass-approvals-and-sandbox` | Override Codex execution flags |
| `CLAUDE_PLUGIN_ROOT` | (auto-resolved) | Plugin directory root for hook path resolution |
