#!/bin/bash
# Codex-first Ralph wrapper
# Usage: ./ralph-codex.sh [--plan-loop] [max_iterations]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/ralph.sh" --tool codex "$@"
