#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${1:?Usage: vm-stop.sh <PROJECT> <ZONE> <VM>}"
PROJECT=$1; ZONE=$2; VM=$3;

log_step "Stopping VM ${VM}..."
gcloud compute instances stop "$VM" --project="$PROJECT" --zone="$ZONE" --quiet
log_info "VM stopped."
