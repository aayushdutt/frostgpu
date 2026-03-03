#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Required variables are validated by lib.sh on load

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
