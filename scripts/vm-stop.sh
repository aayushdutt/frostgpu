#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Required variables are validated by lib.sh on load

log_step "Stopping VM ${VM_NAME}..."
gcloud compute instances stop "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --quiet
log_info "VM stopped."
