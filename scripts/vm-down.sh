#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${1:?Usage: vm-down.sh <PROJECT> <BUCKET> <ZONE> <VM> <VM_USER> [SYNC_DIRS...]}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; VM_USER=${5:-$(whoami)}

trap 'echo ""; log_error "Sync failed! VM is still running. Fix issues and re-run the down command."' ERR

log_step "Syncing to GCS..."
"$SCRIPT_DIR/vm-sync.sh" "$@"

trap - ERR
log_step "Destroying VM..."
gcloud compute instances delete "$VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet > /dev/null
log_info "VM destroyed. No idle costs."