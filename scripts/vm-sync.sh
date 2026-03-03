#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Required variables are validated by lib.sh on load

if [[ "$VM_NAME" == *"-downloader" ]]; then
  log_warn "VM '$VM_NAME' is in Downloader Mode (FUSE). Manual sync is not required."
  exit 0
fi

log_step "Pushing workspace to GCS..."
sync_dirs "down" "$BUCKET" "$VM_USER" "$VM_NAME" "$ZONE" "${SYNC_PAIRS[@]}"
log_info "Sync complete."
