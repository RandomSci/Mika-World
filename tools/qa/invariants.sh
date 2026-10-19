#!/bin/bash
# The invariant suite lives with the shared body (Mika Body, addons/mika_body/qa/invariants.sh); this is a shortcut.
exec "$(cd "$(dirname "$0")/../.." && pwd)/addons/mika_body/qa/invariants.sh" "$@"
