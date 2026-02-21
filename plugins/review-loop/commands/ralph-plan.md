---
description: "Start a Ralph Loop: create a structured plan, get independent Codex review, refine it"
argument-hint: "<task description>"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

First, set up the Ralph plan loop by running this setup command:

```bash
set -e && REVIEW_ID="$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 3 2>/dev/null || head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')" && mkdir -p .claude reviews && if [ -f .claude/ralph-loop.local.md ]; then echo "Error: A review loop is already active. Use /ralph-cancel first." && exit 1; fi && cat > .claude/ralph-loop.local.md << STATE_EOF
---
active: true
phase: ralph-plan
review_id: ${REVIEW_ID}
started_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
---

$ARGUMENTS
STATE_EOF
echo "Ralph Plan Loop activated (ID: ${REVIEW_ID})"
```

After setup completes successfully, create a file called `plan.md` with a structured implementation plan for the task described in the arguments.

The plan MUST use this exact format:

```markdown
# Plan: <descriptive title>

## Phase 1: <phase name>
- [ ] Step 1.1: <step title>
  Description: <what to do>
  Files: <files to create or modify>
  Acceptance: <how to verify this step is done>

- [ ] Step 1.2: <step title>
  Description: <what to do>
  Files: <files to create or modify>
  Acceptance: <how to verify this step is done>

## Phase 2: <phase name>
- [ ] Step 2.1: <step title>
  ...
```

RULES for the plan:
- Each step should be small enough for a single focused implementation pass
- Steps within a phase should be ordered by dependency (earlier steps first)
- Include file paths that will be created or modified
- Include concrete acceptance criteria for each step
- Group related steps into logical phases
- Aim for 3-10 steps total depending on task complexity
- Be specific — vague steps lead to vague implementations

When the plan is complete and written to `plan.md`, stop. The review loop stop hook will automatically:
1. Run Codex for an independent plan review (completeness, ordering, granularity)
2. Present the review for you to address and refine `plan.md`

After the plan is finalized, the user can run the implementation loop:
```
bash plugins/review-loop/scripts/ralph-loop.sh
```
