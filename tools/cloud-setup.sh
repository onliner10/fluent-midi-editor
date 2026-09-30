#!/bin/bash
# Provision a Claude Code cloud session.
#   --force  from the environment's setup script (cached): Python test
#            dependencies and a headless REAPER
#   no args  from the SessionStart hook: Python test dependencies only, and
#            only in cloud sessions; a no-op once they are there
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = true ] || [ "${1:-}" = --force ] || exit 0

if ! python3 -c 'import lupa' 2>/dev/null; then
  python3 -m pip install -q 'lupa>=2.5,<3' 2>/dev/null \
    || python3 -m pip install -q --break-system-packages 'lupa>=2.5,<3'
fi
command -v python >/dev/null || ln -sf "$(command -v python3)" /usr/local/bin/python

if [ "${1:-}" != --force ]; then
  [ -x /opt/fme-reaper/REAPER/reaper ] || echo 'Headless REAPER is not installed: the cloud environment has no setup script (see tools/reaper/README.md). tests/test_reaper.py will be skipped.'
  exit 0
fi

# The setup script pipes this file from GitHub, so install.sh may not be on disk.
here=$(dirname "${BASH_SOURCE[0]:-}")
if [ -f "$here/reaper/install.sh" ]; then
  bash "$here/reaper/install.sh"
else
  curl -fsSL https://raw.githubusercontent.com/onliner10/fluent-midi-editor/main/tools/reaper/install.sh | bash
fi
