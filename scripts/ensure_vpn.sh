#!/usr/bin/env bash
#
# ensure_vpn.sh
# Checks if Yale network is reachable; if not, connects via Cisco Secure Client.
# Can be run standalone or sourced by other scripts.
#
# Usage:
#   ./scripts/ensure_vpn.sh              # connect and verify
#   ./scripts/ensure_vpn.sh --check      # just check, exit 0 if reachable
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.yml"

# Simple YAML reader
_read_config() {
    local key="$1" default="$2"
    local val
    val=$(grep "^${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/[[:space:]]*#.*//' | xargs)
    if [[ -n "$val" ]]; then echo "$val"; else echo "$default"; fi
}

VPN_HOST="access.yale.edu"
LOGIN_NODE="misha.ycrc.yale.edu"
VPN_CLI="/opt/cisco/secureclient/bin/vpn"

# ── Helpers ──────────────────────────────────────────────────────────────────

dns_resolves() {
    host "$LOGIN_NODE" &>/dev/null
}

port_reachable() {
    nc -z -w 3 "$LOGIN_NODE" 22 &>/dev/null
}

yale_network_ok() {
    dns_resolves && port_reachable
}

vpn_is_connected() {
    [[ -x "$VPN_CLI" ]] && echo "state" | "$VPN_CLI" -s 2>/dev/null | grep -q "state: Connected"
}

# ── Connect via GUI ──────────────────────────────────────────────────────────

connect_vpn() {
    echo "==> Launching Cisco Secure Client and connecting to ${VPN_HOST}..."

    osascript <<'APPLESCRIPT'
tell application "Cisco Secure Client" to activate
delay 2
tell application "System Events"
    tell process "Cisco Secure Client"
        set frontmost to true
        delay 0.5
        tell window "Cisco Secure Client"
            click button "Connect"
        end tell
    end tell
end tell
APPLESCRIPT

    # Phase 1: wait for Cisco to report Connected (up to 60s)
    echo "    Waiting for VPN handshake..."
    local i=0
    while (( i < 60 )); do
        if vpn_is_connected; then
            echo "    VPN state: Connected"
            break
        fi
        sleep 1
        (( i++ ))
    done
    if (( i >= 60 )); then
        echo "ERROR: VPN did not connect within 60 seconds." >&2
        exit 1
    fi

    # Phase 2: wait for DNS + route to actually work (up to 30s)
    echo "    Waiting for DNS and network route..."
    local j=0
    while (( j < 30 )); do
        if yale_network_ok; then
            echo "==> VPN connected. ${LOGIN_NODE} is reachable."
            # Close the Chrome tab that Cisco opens on successful auth
            osascript <<'CLOSE_TAB'
delay 1
tell application "Google Chrome"
    set windowCount to count of windows
    repeat with w from 1 to windowCount
        set tabCount to count of tabs of window w
        repeat with t from tabCount to 1 by -1
            if URL of tab t of window w contains "CSCOE" then
                close tab t of window w
                return
            end if
        end repeat
    end repeat
end tell
CLOSE_TAB
            return 0
        fi
        sleep 1
        (( j++ ))
    done

    echo "ERROR: VPN reports connected but ${LOGIN_NODE} is not reachable." >&2
    echo "       DNS resolves: $(dns_resolves && echo yes || echo NO)" >&2
    echo "       Port 22 open: $(port_reachable && echo yes || echo NO)" >&2
    exit 1
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    local check_only=false
    [[ "${1:-}" == "--check" ]] && check_only=true

    if yale_network_ok; then
        echo "==> Yale network reachable (${LOGIN_NODE})."
        return 0
    fi

    if vpn_is_connected; then
        echo "==> VPN is connected but ${LOGIN_NODE} not yet reachable. Waiting..."
        local k=0
        while (( k < 15 )); do
            if yale_network_ok; then
                echo "==> ${LOGIN_NODE} is now reachable."
                return 0
            fi
            sleep 1
            (( k++ ))
        done
        echo "ERROR: VPN connected but cannot reach ${LOGIN_NODE}." >&2
        exit 1
    fi

    if $check_only; then
        echo "NOT connected to Yale network." >&2
        exit 1
    fi

    connect_vpn
}

main "$@"
