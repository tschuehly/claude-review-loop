---
description: "Start a review loop: implement task, get independent Codex review, address feedback"
argument-hint: "<task description>"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - WebSearch
  - WebFetch
  - Task
  - AskUserQuestion
---

First, set up the review loop by running this setup command:

```bash
set -e && REVIEW_ID="$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 3 2>/dev/null || head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')" && STRESS_TEST="false" && if [ -f .claude/stress-test.enabled ] || [ "${REVIEW_LOOP_STRESS_TEST}" = "true" ]; then STRESS_TEST="true"; fi && mkdir -p .claude reviews && if [ -f .claude/review-loop.local.md ]; then echo "Error: A review loop is already active. Use /cancel-review first." && exit 1; fi && cat > .claude/review-loop.local.md << STATE_EOF
---
active: true
phase: task
review_id: ${REVIEW_ID}
stress_test: ${STRESS_TEST}
started_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
---

$ARGUMENTS
STATE_EOF
echo "Review Loop activated (ID: ${REVIEW_ID}, stress-test: ${STRESS_TEST})"
```

After setup completes successfully, read `.claude/review-loop.local.md` and check the `stress_test` field.

**If stress_test is true:**
1. First, create a detailed technical plan for the task
2. Run `/stress-test` to adversarially verify the plan — this checks assumptions against real docs, runs POCs for unverified claims, and updates the plan
3. After stress-test completes, implement the verified plan

**If stress_test is false:**
Proceed directly to implementing the task described in the arguments.

In either case, work thoroughly and completely — write clean, well-structured, well-tested code.

When you believe the task is fully done, stop. The review loop stop hook will automatically:
1. Run Codex for an independent code review
2. Present the review for you to address

RULES:
- Complete the task to the best of your ability before stopping
- Do not stop prematurely or skip parts of the task
- The review loop handles the rest automatically
