#!/usr/bin/env bash
#
# ensure_vpn.sh
# Checks if Yale network is reachable. If not, opens Cisco Secure Client and exits.
#
# Usage:
#   ./scripts/ensure_vpn.sh

set -euo pipefail

LOGIN_NODE="misha.ycrc.yale.edu"

if host "$LOGIN_NODE" &>/dev/null; then
    echo "==> Yale network reachable (${LOGIN_NODE})."
else
    echo "==> Not on Yale network. Opening Cisco Secure Client..."
    open -a "Cisco Secure Client"
    exit 1
fi
