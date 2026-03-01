#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${1:?Usage: vm-sync.sh <PROJECT> <BUCKET> <ZONE> <VM> <VM_USER> [SYNC_DIRS...]}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; VM_USER=${5:-$(whoami)}
shift 5
SYNC_PAIRS=("$@")

log_step "Pushing workspace to GCS..."
sync_dirs "down" "$BUCKET" "$VM_USER" "$VM" "$ZONE" "${SYNC_PAIRS[@]}"
log_info "Sync complete."
