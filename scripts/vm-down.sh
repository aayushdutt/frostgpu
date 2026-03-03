#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Required variables are validated by lib.sh on load

trap 'echo ""; log_error "Sync failed! VM is still running. Fix issues and re-run the down command."' ERR

log_step "Cleaning up persistence..."
if [[ "$VM_NAME" == *"-downloader" ]]; then
  # For downloader, we just unmount. Files are already in GCS.
  unmount_dirs "$VM_USER" "$VM_NAME" "$ZONE" "${SYNC_PAIRS[@]}"
else
  # For GPU machine, we do a final rsync
  "$SCRIPT_DIR/vm-sync.sh"
fi

trap - ERR
log_step "Destroying VM..."
gcloud compute instances delete "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --delete-disks=boot --quiet > /dev/null
log_info "VM destroyed. No idle costs."