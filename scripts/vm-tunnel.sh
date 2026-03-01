#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${1:?Usage: vm-tunnel.sh <VM_USER> <VM_NAME> <ZONE> [FORWARDS...]}"
VM_USER=$1; VM_NAME=$2; ZONE=$3
shift 3
FORWARDS=("$@")

TUNNEL_FLAGS=()
for forward in "${FORWARDS[@]}"; do
  LOCAL="${forward%%:*}"
  REMOTE="${forward#*:}"
  echo "🔌 Forwarding localhost:${LOCAL} → VM:${REMOTE}"
  TUNNEL_FLAGS+=("-L ${LOCAL}:localhost:${REMOTE}")
done

log_step "Connecting to ${VM_NAME}..."
gcloud compute ssh "${VM_USER}@${VM_NAME}" --zone="${ZONE}" \
  "${SSH_FLAGS[@]/#/--ssh-flag=}" \
  "${TUNNEL_FLAGS[@]/#/--ssh-flag=}"
