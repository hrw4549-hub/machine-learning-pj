#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${PJ7_HOME:-$HOME/pj7}/activate.sh"
cd "$SCRIPT_DIR"
GL_BACKEND="${PJ7_GL:-egl}"
mkdir -p logs
python -m pip check
python verify_environment.py --gl "$GL_BACKEND" --output "logs/verification-$GL_BACKEND" "$@"
python verify_act.py --output logs/verification-act.json
