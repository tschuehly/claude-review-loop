---
description: "Run an on-demand Codex code review on existing changes (commit or uncommitted)"
argument-hint: "[git ref]"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

Run Codex to review existing changes. If a git ref is provided, review that commit; otherwise review uncommitted changes.

```bash
set -e

# ── Generate review ID ─────────────────────────────────────────────
REVIEW_ID="$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 3 2>/dev/null || head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')"
REVIEW_FILE="reviews/review-${REVIEW_ID}.md"
mkdir -p reviews

REF="$ARGUMENTS"

# ── Determine diff scope and build prompt ──────────────────────────
if [ -n "$REF" ]; then
  # Validate ref exists
  if ! git rev-parse --verify "$REF" >/dev/null 2>&1; then
    echo "ERROR: '$REF' is not a valid git ref"
    exit 1
  fi
  DIFF_INSTRUCTIONS="Run these commands to see the changes:
- git show $REF --stat  (to see which files changed)
- git show $REF          (to see the full diff)

Review ONLY the changes introduced by commit $REF."
  SCOPE_LABEL="commit $REF"
else
  # Check for uncommitted changes
  if git diff --quiet HEAD 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    echo "ERROR: No uncommitted changes found. Provide a git ref to review a specific commit."
    exit 1
  fi
  DIFF_INSTRUCTIONS="Run these commands to see the changes:
- git diff HEAD --stat   (to see which files changed)
- git diff HEAD          (to see the full diff)

Review ALL uncommitted changes (staged and unstaged)."
  SCOPE_LABEL="uncommitted changes"
fi

CODEX_PROMPT="You are performing a thorough, independent code review of ${SCOPE_LABEL}.

Step 1: Understand the changes
${DIFF_INSTRUCTIONS}
- Read all modified/added files carefully

Step 2: Write your complete review to: ${REVIEW_FILE}

Your review MUST include ALL of these sections:

## Code Quality
- Code organization, modularity, and structure
- Maintainability and readability
- DRY principles and appropriate abstractions
- Naming conventions and consistency

## Test Coverage
- Tests for new/changed functionality
- Edge cases and error paths covered
- Test quality and maintainability

## Security
- Input validation and sanitization
- Authentication/authorization issues
- Injection vulnerabilities (SQL, XSS, command injection)
- Secret/credential exposure risks
- OWASP Top 10 considerations

## Documentation & Agent Harness
- AGENTS.md files in appropriate directories
- CLAUDE.md symlinks for each AGENTS.md
- Telemetry/observability instrumentation
- Type system usage and constraints
- Agent guardrails and setup for success

## UX & Design (SKIP this section entirely if the project has no browser-based UI)
- E2E workflow test coverage
- Visual design quality and consistency
- Accessibility considerations
- Responsive design (test at desktop and mobile viewports)
- If the project has a web UI, use agent-browser for E2E tests and screenshots:
  Install: npm install -g agent-browser (or: brew install agent-browser)
  Navigate the running app, test key workflows, and take screenshots to verify UX.

For each issue found, provide:
1. File path and line number
2. Severity: critical / high / medium / low
3. Category
4. Description
5. Suggested fix

Organize by severity (critical first). End with a summary: total issues, breakdown by severity, overall assessment.

IMPORTANT: Write the FULL review to ${REVIEW_FILE}. You must create that file."

# ── Run Codex ──────────────────────────────────────────────────────
CODEX_FLAGS="${REVIEW_LOOP_CODEX_FLAGS:---dangerously-bypass-approvals-and-sandbox}"

if command -v codex &> /dev/null; then
  echo "Running Codex review of ${SCOPE_LABEL} (ID: ${REVIEW_ID})..."
  # shellcheck disable=SC2086
  codex $CODEX_FLAGS exec "$CODEX_PROMPT" 2>/dev/null || echo "CODEX_FAILED"
else
  echo "CODEX_NOT_FOUND"
fi

# ── Report result ──────────────────────────────────────────────────
if [ -f "$REVIEW_FILE" ]; then
  echo "REVIEW_READY:${REVIEW_FILE}"
else
  echo "REVIEW_MISSING:${REVIEW_FILE}"
fi
```

After the bash block completes, follow these instructions based on the output:

**If the output contains `REVIEW_READY:`** — A review file was created. Do the following:
1. Read the review file indicated in the output
2. For each item in the review, independently decide if you agree
3. For items you AGREE with: implement the fix
4. For items you DISAGREE with: briefly note why you are skipping them
5. Focus on critical and high severity items first
6. Use your own judgment — do not blindly accept every suggestion

**If the output contains `CODEX_NOT_FOUND` or `CODEX_FAILED` or `REVIEW_MISSING:`** — Codex was unavailable or failed. Do a self-review instead:
1. Run `git diff HEAD` (or `git show` for a commit ref) to examine the changes yourself
2. Review for: code quality, security vulnerabilities, test coverage, documentation
3. Report your findings and fix any issues you identify

**If the output contains `ERROR:`** — Report the error to the user and stop.
