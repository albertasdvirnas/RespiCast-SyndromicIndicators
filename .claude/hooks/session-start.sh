#!/bin/bash
# Make the GP-EDM stack available in Claude Code on the web sessions.
#
# Runs synchronously so R, laGP and GPEDM are present before the session
# starts; on a warm container the setup script is a no-op and returns at once.
set -euo pipefail

# Local checkouts are left alone - run scripts/setup-gpedm.sh by hand there.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

"${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/setup-gpedm.sh"
