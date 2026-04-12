#!/usr/bin/env bash
#
# misha_code_session.sh
# Automatically creates a remote code session on the Misha cluster (no GPU),
# waits for the SLURM job to start, and opens VSCode via SSH to the compute node.
#
# Prerequisites:
#   - Connected to Yale VPN
#   - SSH key uploaded to https://sshkeys.ycrc.yale.edu/
#   - VSCode installed with Remote-SSH extension
#
# Usage:
#   ./scripts/misha_code_session.sh [--netid YOUR_NETID] [--time HH:MM:SS] [--mem MEM] [--cpus N]

set -euo pipefail

# ── Load config from config.yml ───────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.yml"

# Simple YAML reader — extracts "key: value" lines (no nested structures)
read_config() {
    local key="$1" default="$2"
    local val
    val=$(grep "^${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/[[:space:]]*#.*//' | xargs)
    if [[ -n "$val" ]]; then echo "$val"; else echo "$default"; fi
}

NETID="$(read_config netid lyz6)"
PARTITION="$(read_config partition devel)"
HOURS="$(read_config hours 2)"
TIME="${HOURS}:00:00"
MEM="$(read_config memory_per_cpu_gib 64)G"
CPUS="$(read_config cpus_per_task 1)"
REMOTE_DIR="$(read_config working_directory '~')"
RESERVATION="$(read_config reservation '')"
CUSTOM_COMMAND="$(read_config custom_command '')"
ADDITIONAL_MODULES="$(read_config additional_modules '')"
SSH_KEY="$(read_config ssh_key_path ~/.ssh/id_ed25519)"
AUTO_CANCEL="$(read_config auto_cancel true)"
AUTO_VPN="$(read_config auto_vpn false)"
POLL_INTERVAL=5
LOGIN_NODE="misha.ycrc.yale.edu"

# ── Optionally ensure VPN connectivity ───────────────────────────────────────
if [[ "$AUTO_VPN" == "true" ]]; then
    "${SCRIPT_DIR}/ensure_vpn.sh"
    echo "==> Waiting for network to stabilize..."
    sleep 5
fi

# ── Pre-load SSH key silently (empty passphrase via SSH_ASKPASS) ─────────────
_ASKPASS=$(mktemp)
printf '#!/bin/sh\necho ""\n' > "$_ASKPASS"
chmod +x "$_ASKPASS"
SSH_ASKPASS="$_ASKPASS" SSH_ASKPASS_REQUIRE=force ssh-add "${SSH_KEY}" </dev/null 2>/dev/null || true
rm -f "$_ASKPASS"

# ── SSH multiplexing (single passphrase prompt) ──────────────────────────────
SSH_SOCKET="/tmp/misha-ssh-control"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ControlMaster=auto -o "ControlPath=${SSH_SOCKET}" -o ControlPersist=600 -o "AddKeysToAgent=yes")

cleanup() {
    ssh -o "ControlPath=${SSH_SOCKET}" -O exit "${SSH_TARGET}" 2>/dev/null || true
}
trap cleanup EXIT

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --netid)     NETID="$2";      shift 2 ;;
        --hours)     TIME="${2}:00:00"; shift 2 ;;
        --mem)       MEM="${2}G";     shift 2 ;;
        --cpus)      CPUS="$2";      shift 2 ;;
        --dir)       REMOTE_DIR="$2"; shift 2 ;;
        --partition) PARTITION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$NETID" ]]; then
    read -rp "Enter your Yale NetID: " NETID
fi

SSH_TARGET="${NETID}@${LOGIN_NODE}"

echo "==> Submitting SLURM job on ${LOGIN_NODE} (partition=${PARTITION}, time=${TIME}, mem-per-cpu=${MEM}, cpus=${CPUS})"

# ── Establish SSH master connection (auto-respond to Duo) ────────────────────
echo "==> Authenticating (Duo push will be sent automatically)..."
SSH_CMD="ssh ${SSH_OPTS[*]} -N -f ${SSH_TARGET}"
expect <<EXPECT_EOF
    set timeout 60
    spawn {*}${SSH_CMD}
    expect {
        "Enter passphrase*"   { send "\r"; exp_continue }
        "Passcode or option*" { send "1\r"; exp_continue }
        "Duo two-factor*"     { exp_continue }
        timeout               { puts "ERROR: SSH auth timed out"; exit 1 }
        eof
    }
EXPECT_EOF
[[ $? -eq 0 ]] || { echo "ERROR: Failed to establish SSH connection." >&2; exit 1; }

# Wait briefly for the control socket to be ready
sleep 1

# ── Build sbatch flags ───────────────────────────────────────────────────────
SBATCH_EXTRA=""
if [[ -n "$RESERVATION" ]]; then
    SBATCH_EXTRA+=" --reservation=${RESERVATION}"
fi

# ── Build the wrap command (load modules + custom command + sleep) ────────────
WRAP_CMD=""
if [[ -n "$ADDITIONAL_MODULES" ]]; then
    WRAP_CMD+="module load ${ADDITIONAL_MODULES}; "
fi
if [[ -n "$CUSTOM_COMMAND" ]]; then
    WRAP_CMD+="${CUSTOM_COMMAND}; "
fi
WRAP_CMD+="sleep infinity"

# ── Submit a batch job that holds the allocation ──────────────────────────────
JOB_ID=$(ssh "${SSH_OPTS[@]}" "$SSH_TARGET" bash <<EOF
sbatch --parsable \
    --partition=${PARTITION} \
    --time=${TIME} \
    --cpus-per-task=${CPUS} \
    --mem-per-cpu=${MEM} \
    --job-name=vscode-session \
    --output=/dev/null \
    ${SBATCH_EXTRA} \
    --wrap="${WRAP_CMD}"
EOF
)

# Strip any trailing whitespace / cluster name from --parsable output
JOB_ID=$(echo "$JOB_ID" | tr -d '[:space:]' | cut -d';' -f1)

if [[ -z "$JOB_ID" ]]; then
    echo "ERROR: Failed to submit SLURM job." >&2
    exit 1
fi

echo "==> Job submitted: ${JOB_ID}"
echo "    (Cancel later with: ssh ${SSH_TARGET} scancel ${JOB_ID})"

# ── Wait for the job to start running ─────────────────────────────────────────
echo "==> Waiting for job to start..."

NODE=""
while true; do
    # Query job state and node list
    JOB_INFO=$(ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "squeue --job ${JOB_ID} --noheader --format='%T %N'" 2>/dev/null || true)

    STATE=$(echo "$JOB_INFO" | awk '{print $1}')
    NODE=$(echo "$JOB_INFO" | awk '{print $2}')

    if [[ -z "$STATE" ]]; then
        echo "ERROR: Job ${JOB_ID} not found — it may have been cancelled or failed." >&2
        exit 1
    fi

    if [[ "$STATE" == "RUNNING" && -n "$NODE" && "$NODE" != "(null)" ]]; then
        echo "==> Job is RUNNING on node: ${NODE}"
        break
    fi

    printf "    Status: %-12s \r" "$STATE"
    sleep "$POLL_INTERVAL"
done

# ── Build the full compute node hostname ──────────────────────────────────────
# Misha nodes are named like r817u09n01; the FQDN is r817u09n01.misha.ycrc.yale.edu
if [[ "$NODE" != *.* ]]; then
    COMPUTE_HOST="${NODE}.misha.ycrc.yale.edu"
else
    COMPUTE_HOST="$NODE"
fi

echo "==> Compute node FQDN: ${COMPUTE_HOST}"

# ── Resolve the VSCode CLI ────────────────────────────────────────────────────
VSCODE_CLI=""
if command -v code &>/dev/null; then
    VSCODE_CLI="code"
elif [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
    VSCODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
fi

# ── Update SSH config so VSCode can reach the compute node via ProxyJump ──────
SSH_CONFIG="$HOME/.ssh/config"
SSH_HOST_ALIAS="misha-compute"
MANAGED_START="# misha-auto-login managed block START"
MANAGED_END="# misha-auto-login managed block END"

# Remove any existing managed block
if grep -q "$MANAGED_START" "$SSH_CONFIG" 2>/dev/null; then
    sed -i.bak "/${MANAGED_START}/,/${MANAGED_END}/d" "$SSH_CONFIG"
    rm -f "${SSH_CONFIG}.bak"
fi

# Append fresh managed block
cat >> "$SSH_CONFIG" <<SSHEOF
${MANAGED_START}
Host misha
    HostName ${LOGIN_NODE}
    User ${NETID}
    ControlPath ${SSH_SOCKET}
    ControlMaster auto
    ControlPersist 600

Host ${SSH_HOST_ALIAS}
    HostName ${COMPUTE_HOST}
    User ${NETID}
    ProxyJump misha
${MANAGED_END}
SSHEOF

echo "==> Updated SSH config: ${SSH_HOST_ALIAS} -> ${COMPUTE_HOST}"

# ── Open VSCode connected to the compute node ────────────────────────────────
echo "==> Opening VSCode connected to ${SSH_HOST_ALIAS} (${COMPUTE_HOST})..."

if [[ -n "$VSCODE_CLI" ]]; then
    if [[ "$AUTO_CANCEL" == "true" ]]; then
        "$VSCODE_CLI" --wait --remote "ssh-remote+${SSH_HOST_ALIAS}" "$REMOTE_DIR"
        echo ""
        echo "==> VSCode window closed. Cancelling SLURM job ${JOB_ID}..."
        ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "scancel ${JOB_ID}" 2>/dev/null || true
        echo "==> Job ${JOB_ID} cancelled."
    else
        "$VSCODE_CLI" --remote "ssh-remote+${SSH_HOST_ALIAS}" "$REMOTE_DIR" &
        echo ""
        echo "Done! You can also connect manually:"
        echo "  ssh ${SSH_HOST_ALIAS}"
        echo ""
        echo "To cancel the SLURM job when you're done:"
        echo "  ssh ${SSH_TARGET} scancel ${JOB_ID}"
        echo ""
        echo "Or run:  ./scripts/misha_cancel.sh ${JOB_ID}"
    fi
else
    echo "WARNING: 'code' CLI not found."
    echo "  Install it from VSCode: Cmd+Shift+P -> 'Shell Command: Install code command in PATH'"
    echo ""
    echo "  Or open VSCode manually and connect to Remote-SSH host: ${SSH_HOST_ALIAS}"
fi
