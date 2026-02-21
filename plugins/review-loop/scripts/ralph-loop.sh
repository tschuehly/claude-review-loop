#!/usr/bin/env bash
set -euo pipefail

# Ralph Loop — Implementation Script
#
# Iterates through steps in plan.md, using claude -p for implementation
# and codex for independent review of each step.
#
# Usage:
#   bash plugins/review-loop/scripts/ralph-loop.sh [--max-iterations N] [--plan FILE]
#
# Resumable: re-run picks up from the last unchecked step.

PLAN_FILE="plan.md"
MAX_ITERATIONS=50
LOG_FILE=".claude/review-loop.log"

log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] ralph-loop: $*" >> "$LOG_FILE"
}

usage() {
  cat << 'HELP'
Usage: bash plugins/review-loop/scripts/ralph-loop.sh [OPTIONS]

Iterates through plan.md steps, implementing each with Claude and reviewing with Codex.

Options:
  --max-iterations N   Maximum steps to process (default: 50)
  --plan FILE          Plan file to use (default: plan.md)
  -h, --help           Show this help

Environment variables:
  REVIEW_LOOP_CODEX_FLAGS  Override codex flags (default: --dangerously-bypass-approvals-and-sandbox)
HELP
  exit 0
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --plan)
      PLAN_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# ── Validate prerequisites ─────────────────────────────────────────
if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: Plan file '$PLAN_FILE' not found."
  echo "Run /ralph-plan first to create a plan."
  exit 1
fi

if ! command -v claude &> /dev/null; then
  echo "Error: 'claude' CLI not found."
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Error: 'jq' is required but not found."
  exit 1
fi

HAS_CODEX=false
if command -v codex &> /dev/null; then
  HAS_CODEX=true
else
  echo "Warning: 'codex' CLI not found. Reviews will be skipped."
fi

CODEX_FLAGS="${REVIEW_LOOP_CODEX_FLAGS:---dangerously-bypass-approvals-and-sandbox}"

# ── Helper: find next unchecked step ────────────────────────────────
# Returns the line number and full step line, or empty if all done.
find_next_step() {
  grep -n '^\- \[ \] Step [0-9]' "$PLAN_FILE" | head -1
}

# ── Helper: mark step complete in plan.md ───────────────────────────
mark_step_complete() {
  local line_num="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "${line_num}s/^- \[ \] /- [x] /" "$PLAN_FILE"
  else
    sed -i "${line_num}s/^- \[ \] /- [x] /" "$PLAN_FILE"
  fi
}

# ── Helper: extract step info ───────────────────────────────────────
# Extracts the step block (title + indented lines below it) from plan.md
extract_step_block() {
  local line_num="$1"
  local total_lines
  total_lines=$(wc -l < "$PLAN_FILE")

  # Get the step title line
  local step_line
  step_line=$(sed -n "${line_num}p" "$PLAN_FILE")

  # Collect indented continuation lines (Description, Files, Acceptance, etc.)
  local block="$step_line"
  local next=$((line_num + 1))
  while [ "$next" -le "$total_lines" ]; do
    local next_line
    next_line=$(sed -n "${next}p" "$PLAN_FILE")
    # Stop at blank lines, new steps, or new phase headers
    if echo "$next_line" | grep -qE '^(- \[|## |# |$)'; then
      break
    fi
    block="$block
$next_line"
    next=$((next + 1))
  done

  echo "$block"
}

# ── Main loop ───────────────────────────────────────────────────────
echo ""
echo "Ralph Loop — Starting implementation"
echo "  Plan: $PLAN_FILE"
echo "  Max iterations: $MAX_ITERATIONS"
echo "  Codex: $([ "$HAS_CODEX" = true ] && echo "available" || echo "skipping reviews")"
echo ""

mkdir -p reviews

ITERATION=0
while [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; do
  # Find next unchecked step
  NEXT=$(find_next_step)
  if [ -z "$NEXT" ]; then
    echo ""
    echo "All steps complete!"
    log "All steps complete after $ITERATION iterations"
    break
  fi

  ITERATION=$((ITERATION + 1))
  LINE_NUM=$(echo "$NEXT" | cut -d: -f1)
  STEP_TITLE=$(echo "$NEXT" | cut -d: -f2- | sed 's/^- \[ \] //')
  STEP_BLOCK=$(extract_step_block "$LINE_NUM")

  # Generate review ID for this iteration
  if command -v openssl &> /dev/null; then
    RAND_HEX=$(openssl rand -hex 3)
  else
    RAND_HEX=$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')
  fi
  STEP_REVIEW_ID="$(date +%Y%m%d-%H%M%S)-${RAND_HEX}"

  echo "────────────────────────────────────────────────────────"
  echo "Iteration $ITERATION: $STEP_TITLE"
  echo "────────────────────────────────────────────────────────"
  log "Starting iteration $ITERATION: $STEP_TITLE (review_id=$STEP_REVIEW_ID)"

  # ── Step 1: Claude implements the step ──────────────────────────
  PROGRESS_CONTEXT=""
  if [ -f progress.txt ]; then
    PROGRESS_CONTEXT="

Previous progress:
$(cat progress.txt)"
  fi

  IMPLEMENT_PROMPT="You are implementing a step from an implementation plan.

Full plan (plan.md):
$(cat "$PLAN_FILE")
${PROGRESS_CONTEXT}

YOUR CURRENT TASK:
${STEP_BLOCK}

Instructions:
1. Implement ONLY this specific step — do not work on other steps
2. Write clean, well-structured code
3. Follow existing project conventions
4. After implementing, update progress.txt with a brief summary of what you did
5. Do NOT modify plan.md — the orchestration script handles step tracking

Focus on this step only. Be thorough but stay scoped."

  echo "  [1/3] Implementing with Claude..."
  log "Running claude -p for implementation"
  claude -p --permission-mode acceptEdits "$IMPLEMENT_PROMPT" 2>/dev/null || {
    echo "  ERROR: Claude implementation failed for this step"
    log "ERROR: claude -p failed for iteration $ITERATION"
    echo "  Stopping loop. Fix the issue and re-run to resume."
    exit 1
  }

  # ── Step 2: Codex reviews the changes ───────────────────────────
  REVIEW_FILE="reviews/ralph-review-${STEP_REVIEW_ID}.md"
  if [ "$HAS_CODEX" = true ]; then
    echo "  [2/3] Codex reviewing changes..."
    log "Running codex review (review_id=$STEP_REVIEW_ID)"

    REVIEW_PROMPT="You are reviewing code changes for this implementation step:

${STEP_BLOCK}

Step 1: Understand the changes
- Run git diff to see what changed
- Read modified files

Step 2: Write your review to: ${REVIEW_FILE}

Focus on:
- Correctness: Does the implementation match the step's requirements?
- Code quality: Clean, readable, maintainable?
- Security: Any vulnerabilities introduced?
- Test coverage: Are changes tested?

For each issue, provide: file path, severity (critical/high/medium/low), description, suggested fix.

IMPORTANT: Write the FULL review to ${REVIEW_FILE}."

    # shellcheck disable=SC2086
    codex $CODEX_FLAGS exec "$REVIEW_PROMPT" >/dev/null 2>&1 || {
      log "WARN: codex review failed for iteration $ITERATION"
    }
  else
    echo "  [2/3] Skipping review (codex not available)"
  fi

  # ── Step 3: Claude addresses review feedback ────────────────────
  if [ -f "$REVIEW_FILE" ]; then
    echo "  [3/3] Addressing review feedback..."
    log "Running claude -p to address review"

    ADDRESS_PROMPT="You are addressing code review feedback.

Review file: ${REVIEW_FILE}
$(cat "$REVIEW_FILE")

Step being reviewed:
${STEP_BLOCK}

Instructions:
1. Read each review item carefully
2. For items you AGREE with: implement the fix
3. For items you DISAGREE with: skip them (they are suggestions, not mandates)
4. Focus on critical and high severity items
5. After addressing, update progress.txt with what you fixed
6. Do NOT modify plan.md

Use your own judgment. Do not blindly accept every suggestion."

    claude -p --permission-mode acceptEdits "$ADDRESS_PROMPT" 2>/dev/null || {
      log "WARN: claude -p address phase failed for iteration $ITERATION"
    }
  else
    echo "  [3/3] No review to address"
  fi

  # ── Mark step complete ──────────────────────────────────────────
  mark_step_complete "$LINE_NUM"
  log "Completed iteration $ITERATION: $STEP_TITLE"
  echo "  Done: $STEP_TITLE"
  echo ""
done

if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
  echo ""
  echo "Reached max iterations ($MAX_ITERATIONS). Re-run to continue."
  log "Stopped at max iterations ($MAX_ITERATIONS)"
fi

echo ""
echo "Ralph Loop finished. $ITERATION step(s) processed."
echo "See progress.txt for implementation summary."
echo "See reviews/ for step-by-step review artifacts."
