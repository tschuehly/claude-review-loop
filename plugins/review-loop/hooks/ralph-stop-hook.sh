#!/usr/bin/env bash
# Ralph Loop — Stop Hook
#
# Two-phase lifecycle for plan creation:
#   Phase 1 (ralph-plan):       Claude creates plan.md → hook runs Codex plan review → blocks exit
#   Phase 2 (ralph-addressing): Claude refines plan → hook allows exit
#
# On any error, default to allowing exit (never trap the user in a broken loop).
#
# Environment variables:
#   REVIEW_LOOP_CODEX_FLAGS  Override codex flags (default: --dangerously-bypass-approvals-and-sandbox)

LOG_FILE=".claude/ralph-loop.log"

log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$LOG_FILE"
}

trap 'log "ERROR: hook exited via ERR trap (line $LINENO)"; printf "{\"decision\":\"approve\"}\n"; exit 0' ERR

# Consume stdin (hook input JSON) — must read to avoid broken pipe
HOOK_INPUT=$(cat)

STATE_FILE=".claude/ralph-loop.local.md"

# No active loop → allow exit
if [ ! -f "$STATE_FILE" ]; then
  printf '{"decision":"approve"}\n'
  exit 0
fi

# Parse a field from the YAML frontmatter
parse_field() {
  sed -n "s/^${1}: *//p" "$STATE_FILE" | head -1
}

ACTIVE=$(parse_field "active")
PHASE=$(parse_field "phase")
REVIEW_ID=$(parse_field "review_id")

# Not active → clean up and exit
if [ "$ACTIVE" != "true" ]; then
  rm -f "$STATE_FILE"
  printf '{"decision":"approve"}\n'
  exit 0
fi

# Validate review_id format to prevent path traversal
if ! echo "$REVIEW_ID" | grep -qE '^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$'; then
  log "ERROR: invalid review_id format: $REVIEW_ID"
  rm -f "$STATE_FILE"
  printf '{"decision":"approve"}\n'
  exit 0
fi

# Safety: if stop_hook_active is true and we're still in "ralph-plan" phase,
# something went wrong with the phase transition. Allow exit to prevent loops.
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [ "$STOP_HOOK_ACTIVE" = "true" ] && [ "$PHASE" = "ralph-plan" ]; then
  log "WARN: stop_hook_active=true in ralph-plan phase, aborting to prevent loop"
  rm -f "$STATE_FILE"
  printf '{"decision":"approve"}\n'
  exit 0
fi

case "$PHASE" in
  ralph-plan)
    # ── Phase 1 → 2: Run Codex for plan review ──────────────────────
    REVIEW_FILE="reviews/plan-review-${REVIEW_ID}.md"
    mkdir -p reviews

    CODEX_PROMPT="You are reviewing an implementation plan in plan.md for completeness, ordering, and quality.

Step 1: Read the plan
- Read plan.md carefully
- Understand the overall task and each step

Step 2: Write your review to: ${REVIEW_FILE}

Your review MUST evaluate:

## Completeness
- Are all necessary steps included?
- Are there missing dependencies or prerequisites?
- Does the plan cover error handling and edge cases?

## Ordering & Dependencies
- Are steps ordered correctly by dependency?
- Can any steps be parallelized?
- Are there circular dependencies?

## Granularity
- Is each step small enough for a single focused implementation pass?
- Are any steps too large and should be broken down?
- Are any steps too small and should be combined?

## Testability
- Does each step have clear acceptance criteria?
- Are the acceptance criteria verifiable?
- Is there adequate test coverage planned?

## File Coverage
- Are all files that need modification identified?
- Are there files that will be affected but aren't listed?

For each issue found, provide:
1. Step reference (e.g., Step 2.3)
2. Severity: critical / high / medium / low
3. Category (completeness / ordering / granularity / testability / files)
4. Description
5. Suggested improvement

End with a summary: overall assessment, total issues by severity, and whether the plan is ready for implementation.

IMPORTANT: Write the FULL review to ${REVIEW_FILE}. You must create that file."

    CODEX_FLAGS="${REVIEW_LOOP_CODEX_FLAGS:---dangerously-bypass-approvals-and-sandbox}"
    CODEX_EXIT=0
    START_TIME=$(date +%s)

    if command -v codex &> /dev/null; then
      log "Starting Codex plan review (flags: $CODEX_FLAGS)"
      # shellcheck disable=SC2086
      codex $CODEX_FLAGS exec "$CODEX_PROMPT" >/dev/null 2>&1 || CODEX_EXIT=$?
      ELAPSED=$(( $(date +%s) - START_TIME ))
      log "Codex plan review finished (exit=$CODEX_EXIT, elapsed=${ELAPSED}s)"
    else
      log "WARN: codex not found, skipping independent plan review"
    fi

    # Transition to ralph-addressing phase
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/^phase: ralph-plan$/phase: ralph-addressing/' "$STATE_FILE"
    else
      sed -i 's/^phase: ralph-plan$/phase: ralph-addressing/' "$STATE_FILE"
    fi

    if [ -f "$REVIEW_FILE" ]; then
      REASON="IMPORTANT: Before addressing the review, run /compact to compress your conversation context. Your plan creation work is complete and the full context from that phase is no longer needed.

After compacting, read the independent plan review at ${REVIEW_FILE} and refine plan.md:
1. Read the review carefully
2. For each item, independently decide if you agree
3. For items you AGREE with: update plan.md accordingly
4. For items you DISAGREE with: briefly note why you are skipping them
5. Focus on critical and high severity items first
6. When done refining the plan, you may stop

Use your own judgment. Do not blindly accept every suggestion."
    else
      REASON="IMPORTANT: Before proceeding, run /compact to compress your conversation context. Your plan creation work is complete and the full context from that phase is no longer needed.

Codex was unable to complete the plan review (${REVIEW_FILE} not found). This may mean codex is not installed or timed out.

Please do a brief self-review of plan.md covering:
- Completeness (all necessary steps included?)
- Ordering (dependencies correct?)
- Granularity (steps appropriately sized?)
- Testability (clear acceptance criteria?)

Refine plan.md as needed, then you may stop."
    fi

    SYS_MSG="Ralph Plan [${REVIEW_ID}] — Phase 2/2: Compact context, then address plan review feedback"

    jq -n --arg r "$REASON" --arg s "$SYS_MSG" \
      '{decision:"block", reason:$r, systemMessage:$s}'
    ;;

  ralph-addressing)
    # ── Phase 2 complete: plan refined. Allow exit. ──────────────────
    log "Ralph plan loop complete (review_id=$REVIEW_ID)"
    rm -f "$STATE_FILE"
    printf '{"decision":"approve"}\n'
    ;;

  *)
    # Unknown phase — clean up and allow exit
    log "WARN: unknown phase '$PHASE', cleaning up"
    rm -f "$STATE_FILE"
    printf '{"decision":"approve"}\n'
    ;;
esac
