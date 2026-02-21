# review-loop

A Claude Code plugin that adds an automated code review loop and a plan-then-implement workflow to your development process.

## What it does

This plugin provides two workflows:

### Review Loop (`/review-loop`)

A two-phase code review lifecycle:

1. **Task phase**: You describe a task, Claude implements it
2. **Review phase**: When Claude finishes, the stop hook automatically runs [Codex](https://github.com/openai/codex) for an independent code review, then asks Claude to address the feedback

The result: every task gets an independent second opinion before you accept the changes.

### Ralph Loop (`/ralph-plan` + `ralph-loop.sh`)

A plan-then-implement workflow for larger tasks:

1. **Plan phase**: You describe a task, Claude creates a structured `plan.md` with phased steps
2. **Plan review**: The stop hook runs Codex to review the plan for completeness, ordering, and granularity
3. **Plan refinement**: Claude addresses the plan review feedback
4. **Implementation**: An external script iterates through each step — implementing with Claude, reviewing with Codex, and addressing feedback automatically

The result: large tasks are broken into reviewable steps, each independently implemented and reviewed.

## Review coverage

The Codex code review covers:

- **Code quality** — organization, modularity, DRY, naming
- **Test coverage** — new tests, edge cases, test quality
- **Security** — input validation, injection, secrets, OWASP top 10
- **Documentation & agent harness** — AGENTS.md, CLAUDE.md symlinks, telemetry, type system, agent guardrails
- **UX & design** (for UI projects) — E2E tests, visual quality, accessibility

The Codex plan review covers:

- **Completeness** — all necessary steps, missing dependencies
- **Ordering** — correct dependency order, parallelization opportunities
- **Granularity** — steps appropriately sized for single implementation passes
- **Testability** — clear, verifiable acceptance criteria
- **File coverage** — all affected files identified

## Requirements

- [Claude Code](https://claude.ai/code) (CLI)
- `jq` — `brew install jq` (macOS) / `apt install jq` (Linux)
- [Codex CLI](https://github.com/openai/codex) (recommended) — `npm install -g @openai/codex`. Without Codex, the plugin falls back to asking Claude to self-review.

## Installation

From the CLI:

```bash
claude plugin marketplace add hamelsmu/claude-review-loop
claude plugin install review-loop@hamel-review
```

Or from within a Claude Code session:

```
/plugin marketplace add hamelsmu/claude-review-loop
/plugin install review-loop@hamel-review
```


## Usage

### Review Loop

Start a review loop:

```
/review-loop Add user authentication with JWT tokens and test coverage
```

Claude will implement the task. When it finishes, the stop hook:
1. Runs `codex exec` for an independent review
2. Writes findings to `reviews/review-<id>.md`
3. Blocks Claude's exit and asks it to address the feedback
4. Claude addresses items it agrees with, then stops

Cancel a review loop:

```
/cancel-review
```

### Ralph Loop

#### Step 1: Create and review the plan

In a Claude Code session:

```
/ralph-plan Add a REST API with user CRUD, authentication, and rate limiting
```

Claude creates `plan.md` with structured, phased steps. When it finishes:
1. The stop hook runs Codex to review the plan
2. Claude addresses the plan review feedback and refines `plan.md`
3. Claude exits — you now have a reviewed plan

#### Step 2: Review the plan yourself

Open `plan.md` and make any final adjustments. The format looks like:

```markdown
# Plan: REST API with Authentication

## Phase 1: Core Setup
- [ ] Step 1.1: Set up Express server with project structure
  Description: Initialize the project with Express, configure middleware...
  Files: src/index.ts, src/routes/, package.json
  Acceptance: Server starts, health check endpoint returns 200

- [ ] Step 1.2: Add database models
  Description: Create User model with Sequelize...
  Files: src/models/user.ts, src/db.ts
  Acceptance: Migrations run, User table created

## Phase 2: Authentication
- [ ] Step 2.1: Implement JWT auth
  ...
```

#### Step 3: Run the implementation loop

From your terminal:

```bash
bash plugins/review-loop/scripts/ralph-loop.sh
```

The script iterates through each unchecked step:
1. Runs `claude -p` to implement the step
2. Runs `codex` to review the changes
3. Runs `claude -p` to address review feedback
4. Marks the step complete in `plan.md` (`- [x]`)
5. Repeats until all steps are done

Options:

```bash
# Limit to 5 steps
bash plugins/review-loop/scripts/ralph-loop.sh --max-iterations 5

# Use a different plan file
bash plugins/review-loop/scripts/ralph-loop.sh --plan my-plan.md
```

The loop is **resumable** — if interrupted, re-run the script and it picks up from the last unchecked step.

Cancel a Ralph plan loop (during the plan creation phase):

```
/ralph-cancel
```

### What happens if Codex isn't installed?

Both workflows gracefully degrade:
- **Review Loop**: Falls back to asking Claude to self-review its changes
- **Ralph Loop plan phase**: Falls back to Claude self-reviewing the plan
- **Ralph Loop implementation**: Skips the Codex review step entirely (implement only)

## How it works

Both workflows use **Stop hooks** — Claude Code's mechanism for intercepting agent exit.

### Review Loop

When Claude tries to stop:
1. The hook reads `.claude/review-loop.local.md`
2. If in `task` phase: runs Codex code review, transitions to `addressing`, blocks exit
3. If in `addressing` phase: allows exit, cleans up

### Ralph Loop

The plan phase uses a separate stop hook:
1. The hook reads `.claude/ralph-loop.local.md`
2. If in `ralph-plan` phase: runs Codex plan review, transitions to `ralph-addressing`, blocks exit
3. If in `ralph-addressing` phase: allows exit, cleans up

The implementation phase (`ralph-loop.sh`) runs outside of Claude Code as a standalone script that orchestrates `claude -p` and `codex` invocations.

## File structure

```
plugins/review-loop/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest (source of truth for version)
├── commands/
│   ├── review-loop.md           # /review-loop slash command
│   ├── cancel-review.md         # /cancel-review slash command
│   ├── review.md                # /review on-demand review command
│   ├── ralph-plan.md            # /ralph-plan slash command
│   └── ralph-cancel.md          # /ralph-cancel slash command
├── hooks/
│   ├── hooks.json               # Stop hook registration (900s timeout)
│   ├── stop-hook.sh             # Review loop lifecycle engine
│   └── ralph-stop-hook.sh       # Ralph loop lifecycle engine
├── scripts/
│   ├── setup-review-loop.sh     # Review loop setup with dependency checks
│   └── ralph-loop.sh            # Ralph implementation loop script
├── AGENTS.md                    # Agent operating guidelines
└── CLAUDE.md                    # Symlink → AGENTS.md
```

## Configuration

The stop hook timeout is set to 900 seconds (15 minutes) in `hooks/hooks.json`. Adjust if your Codex reviews take longer.

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REVIEW_LOOP_CODEX_FLAGS` | `--dangerously-bypass-approvals-and-sandbox` | Flags passed to `codex`. Set to `--sandbox workspace-write` for safer sandboxed reviews. |

### Telemetry

Execution logs are written to `.claude/review-loop.log` (review loop) and `.claude/ralph-loop.log` (ralph loop) with timestamps, codex exit codes, and elapsed times. Both files are gitignored.

## Credits

Inspired by the [Ralph Wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) and [Ryan Carson's compound engineering loop](https://x.com/ryancarson/article/2016520542723924279).
