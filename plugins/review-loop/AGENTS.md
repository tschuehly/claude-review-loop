# review-loop Plugin — Agent Guidelines

## What this is

A Claude Code plugin with two workflows:

**Review Loop** (`/review-loop`): Two-phase code review loop:
1. Claude implements a task
2. Codex independently reviews the changes
3. Claude addresses the review feedback

**Ralph Loop** (`/ralph-plan` + `ralph-loop.sh`): Plan-then-implement workflow:
1. Claude creates a structured `plan.md` with phased steps
2. Codex reviews the plan for completeness, ordering, granularity
3. Claude refines the plan based on feedback
4. External script iterates through steps: implement → review → address → commit

## State Machines

Each workflow has its own state file, stop hook, and log file.

### Review Loop
- State: `.claude/review-loop.local.md` | Hook: `hooks/stop-hook.sh` | Log: `.claude/review-loop.log`
- `task` → Claude implementing. Stop hook runs Codex code review, transitions to `addressing`.
- `addressing` → Claude addressing review. Stop hook approves exit, removes state.

### Ralph Loop
- State: `.claude/ralph-loop.local.md` | Hook: `hooks/ralph-stop-hook.sh` | Log: `.claude/ralph-loop.log`
- `ralph-plan` → Claude creating plan.md. Stop hook runs Codex plan review, transitions to `ralph-addressing`.
- `ralph-addressing` → Claude refining plan. Stop hook approves exit, removes state.

## plan.md Format

```markdown
# Plan: <descriptive title>

## Phase 1: <phase name>
- [ ] Step 1.1: <step title>
  Description: <what to do>
  Files: <files to create or modify>
  Acceptance: <how to verify this step is done>
```

- Steps are checked off (`- [x]`) by `ralph-loop.sh` as they complete
- `progress.txt` (gitignored) tracks implementation progress across iterations

## ralph-loop.sh

External shell script for automated step-by-step implementation.

```bash
bash plugins/review-loop/scripts/ralph-loop.sh [--max-iterations N] [--plan FILE]
```

Each iteration:
1. Finds next unchecked step in plan.md
2. Runs `claude -p` to implement the step
3. Runs `codex` to review changes (skipped if unavailable)
4. Runs `claude -p` to address review feedback
5. Marks step complete in plan.md
6. Repeats until all done or max iterations reached

Resumable: interrupted runs pick up from the last unchecked step.

## Conventions

- Shell scripts must work on both macOS and Linux (handle `sed -i` differences)
- The stop hook MUST always produce valid JSON to stdout — never let non-JSON text leak
- Fail-open: on any error, approve exit rather than trapping the user
- Review loop state in `.claude/review-loop.local.md`, Ralph state in `.claude/ralph-loop.local.md` — always clean up on exit
- Review ID format: `YYYYMMDD-HHMMSS-hexhex` — validate before using in paths
- Codex stdout/stderr is redirected away from hook stdout to prevent JSON corruption
- Telemetry goes to `.claude/review-loop.log` and `.claude/ralph-loop.log` — structured, timestamped lines

## Security constraints

- Review IDs are validated against `^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$` to prevent path traversal
- Codex flags are configurable via `REVIEW_LOOP_CODEX_FLAGS` env var
- No secrets or credentials are stored in state files

## Testing

- After modifying stop-hook.sh, test: no-state→approve, task→addressing, addressing→approve
- After modifying ralph-stop-hook.sh, test: no-state→approve, ralph-plan→ralph-addressing, ralph-addressing→approve
- Verify JSON output with `jq .` for each path
- Test with codex unavailable (should fall back to self-review prompt)
- Test with malformed state files (should fail-open)
- Test ralph-loop.sh with a simple 2-step plan.md
