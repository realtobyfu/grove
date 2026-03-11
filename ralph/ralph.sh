#!/bin/bash
# Ralph loop runner (Huntley flavor friendly)
# Usage: ./ralph.sh [--tool amp|claude|codex] [--plan-loop] [--prompt FILE] [max_iterations]

set -e

TOOL="claude"
MAX_ITERATIONS=10
PROMPT_FILE="CLAUDE.md"
CODEX_PROMPT_FILE="CODEX.md"
PLAN_PROMPT_FILE="PLAN.md"
CODEX_PLAN_PROMPT_FILE="CODEX_PLAN.md"
LAST_MESSAGE_FILE=".ralph-last-message.txt"
SLEEP_SECONDS=2
PLAN_LOOP=false
ITERATIONS_SET=false
PROMPT_OVERRIDDEN=false
PROMPT_OVERRIDE_VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --plan-loop)
      PLAN_LOOP=true
      shift
      ;;
    --prompt)
      PROMPT_OVERRIDE_VALUE="$2"
      PROMPT_OVERRIDDEN=true
      shift 2
      ;;
    --prompt=*)
      PROMPT_OVERRIDE_VALUE="${1#*=}"
      PROMPT_OVERRIDDEN=true
      shift
      ;;
    --sleep)
      SLEEP_SECONDS="$2"
      shift 2
      ;;
    --sleep=*)
      SLEEP_SECONDS="${1#*=}"
      shift
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
        ITERATIONS_SET=true
      fi
      shift
      ;;
  esac
done

if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "codex" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'codex'."
  exit 1
fi

# Planning runs are usually one-shot unless explicitly overridden.
if [[ "$PLAN_LOOP" == true && "$ITERATIONS_SET" == false ]]; then
  MAX_ITERATIONS=1
fi

if [[ "$MAX_ITERATIONS" -le 0 ]]; then
  echo "No iterations requested. Exiting."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAST_MESSAGE_PATH="$SCRIPT_DIR/$LAST_MESSAGE_FILE"
RUN_MODE="execute"
if [[ "$PLAN_LOOP" == true ]]; then
  RUN_MODE="plan"
fi

if [[ "$PROMPT_OVERRIDDEN" == true ]]; then
  ACTIVE_PROMPT_PATH="$SCRIPT_DIR/$PROMPT_OVERRIDE_VALUE"
else
  if [[ "$TOOL" == "codex" ]]; then
    if [[ "$PLAN_LOOP" == true ]]; then
      ACTIVE_PROMPT_PATH="$SCRIPT_DIR/$CODEX_PLAN_PROMPT_FILE"
    else
      ACTIVE_PROMPT_PATH="$SCRIPT_DIR/$CODEX_PROMPT_FILE"
    fi
  else
    if [[ "$PLAN_LOOP" == true ]]; then
      ACTIVE_PROMPT_PATH="$SCRIPT_DIR/$PLAN_PROMPT_FILE"
    else
      ACTIVE_PROMPT_PATH="$SCRIPT_DIR/$PROMPT_FILE"
    fi
  fi
fi

if [[ ! -f "$ACTIVE_PROMPT_PATH" ]]; then
  EXAMPLE_PROMPT_PATH="$SCRIPT_DIR/examples/$(basename "$ACTIVE_PROMPT_PATH")"
  if [[ -f "$EXAMPLE_PROMPT_PATH" ]]; then
    ACTIVE_PROMPT_PATH="$EXAMPLE_PROMPT_PATH"
  else
    echo "Error: Missing prompt file: $ACTIVE_PROMPT_PATH"
    exit 1
  fi
fi

echo "Starting Ralph - Mode: $RUN_MODE - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"
echo "Prompt file: $ACTIVE_PROMPT_PATH"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL/$RUN_MODE)"
  echo "==============================================================="

  rm -f "$LAST_MESSAGE_PATH"
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cat "$ACTIVE_PROMPT_PATH" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  elif [[ "$TOOL" == "claude" ]]; then
    OUTPUT=$(claude --dangerously-skip-permissions --print < "$ACTIVE_PROMPT_PATH" 2>&1 | tee /dev/stderr) || true
  else
    OUTPUT=$(codex exec --dangerously-bypass-approvals-and-sandbox --output-last-message "$LAST_MESSAGE_PATH" < "$ACTIVE_PROMPT_PATH" 2>&1 | tee /dev/stderr) || true
  fi

  COMPLETION_TEXT="$OUTPUT"
  if [[ "$TOOL" == "codex" && -f "$LAST_MESSAGE_PATH" ]]; then
    COMPLETION_TEXT="$(cat "$LAST_MESSAGE_PATH")"
  fi

  if echo "$COMPLETION_TEXT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep "$SLEEP_SECONDS"
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
exit 1
