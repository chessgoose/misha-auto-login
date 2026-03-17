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

# ── Defaults ──────────────────────────────────────────────────────────────────
NETID="${MISHA_NETID:-lyz6}"
PARTITION="devel"
TIME="6:00:00"
MEM="10G"
CPUS=1
REMOTE_DIR="~"
POLL_INTERVAL=5
LOGIN_NODE="misha.ycrc.yale.edu"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --netid)   NETID="$2";      shift 2 ;;
        --time)    TIME="$2";       shift 2 ;;
        --mem)     MEM="$2";        shift 2 ;;
        --cpus)    CPUS="$2";       shift 2 ;;
        --dir)     REMOTE_DIR="$2"; shift 2 ;;
        --partition) PARTITION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$NETID" ]]; then
    read -rp "Enter your Yale NetID: " NETID
fi

SSH_TARGET="${NETID}@${LOGIN_NODE}"

echo "==> Submitting SLURM job on ${LOGIN_NODE} (partition=${PARTITION}, time=${TIME}, mem=${MEM}, cpus=${CPUS})"

# ── Submit a batch job that just sleeps (holds the allocation) ────────────────
JOB_ID=$(ssh -o StrictHostKeyChecking=accept-new "$SSH_TARGET" bash <<EOF
sbatch --parsable \
    --partition=${PARTITION} \
    --time=${TIME} \
    --cpus-per-task=${CPUS} \
    --mem=${MEM} \
    --job-name=vscode-session \
    --output=/dev/null \
    --wrap="sleep infinity"
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
    JOB_INFO=$(ssh "$SSH_TARGET" "squeue --job ${JOB_ID} --noheader --format='%T %N'" 2>/dev/null || true)

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

# ── Configure SSH for ProxyJump through the login node ────────────────────────
SSH_CONFIG="$HOME/.ssh/config"
MARKER="# misha-auto-login managed block"

# Remove any previous managed block
if [[ -f "$SSH_CONFIG" ]]; then
    sed -i.bak "/${MARKER} START/,/${MARKER} END/d" "$SSH_CONFIG"
fi

cat >> "$SSH_CONFIG" <<SSHEOF
${MARKER} START
Host misha-login
    HostName ${LOGIN_NODE}
    User ${NETID}

Host misha-compute
    HostName ${COMPUTE_HOST}
    User ${NETID}
    ProxyJump misha-login
${MARKER} END
SSHEOF

echo "==> Updated ~/.ssh/config with misha-compute entry (via ProxyJump)"

# ── Open VSCode connected to the compute node ────────────────────────────────
echo "==> Opening VSCode connected to ${COMPUTE_HOST}..."

code --remote "ssh-remote+misha-compute" "$REMOTE_DIR" 2>/dev/null &

echo ""
echo "Done! VSCode should open shortly."
echo ""
echo "To cancel the SLURM job when you're done:"
echo "  ssh ${SSH_TARGET} scancel ${JOB_ID}"
echo ""
echo "Or run:  ./scripts/misha_cancel.sh ${JOB_ID}"
