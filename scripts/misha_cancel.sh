#!/usr/bin/env bash
# Cancel a Misha SLURM job by ID.
# Usage: ./scripts/misha_cancel.sh JOB_ID [--netid NETID]

set -euo pipefail

JOB_ID="${1:-}"
NETID="${MISHA_NETID:-lyz6}"

shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --netid) NETID="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "$JOB_ID" ]]; then
    echo "Usage: $0 JOB_ID [--netid NETID]" >&2
    exit 1
fi

if [[ -z "$NETID" ]]; then
    read -rp "Enter your Yale NetID: " NETID
fi

echo "Cancelling job ${JOB_ID}..."
ssh "${NETID}@misha.ycrc.yale.edu" "scancel ${JOB_ID}"
echo "Job ${JOB_ID} cancelled."
