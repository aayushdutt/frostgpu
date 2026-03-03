#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

log_step "Connecting to ${VM_NAME}..."
gcloud compute ssh "${VM_USER}@${VM_NAME}" --zone="${ZONE}" \
  "${SSH_FLAGS[@]/#/--ssh-flag=}"
