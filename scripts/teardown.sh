#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${1:?Usage: teardown.sh <PROJECT> <BUCKET> <ZONE> <VM> <SNAPSHOT>}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; SNAP=$5

log_step "Scanning GCP resources..."

# 1. Resolve resources
VM_UP=$(vm_exists "$PROJECT" "$ZONE" "$VM" && echo true || echo false)
DL_VM="${VM}-downloader"
DL_VM_UP=$(vm_exists "$PROJECT" "$ZONE" "$DL_VM" && echo true || echo false)
BUCKET_UP=$(bucket_exists "$PROJECT" "$BUCKET" && echo true || echo false)
ALL_SNAPS=$(gcloud compute snapshots list \
  --project="$PROJECT" --filter="name~^${SNAP}" --format="value(name)" 2>/dev/null)

log_step "The following resources will be PERMANENTLY DELETED:"
[[ "$VM_UP" == "true" ]] && echo "   🖥  VM:        $VM ($ZONE)" || echo "   🖥  VM:        (not found)"
[[ "$DL_VM_UP" == "true" ]] && echo "   🖥  VM:        $DL_VM ($ZONE)" || true
if [[ -n "$ALL_SNAPS" ]]; then
  while IFS= read -r s; do echo "   📸 Snapshot:  $s"; done <<< "$ALL_SNAPS"
else
  echo "   📸 Snapshots: (none found)"
fi
[[ "$BUCKET_UP" == "true" ]] && echo "   🪣 Bucket:    $BUCKET (ALL contents)" || echo "   🪣 Bucket:    (not found)"

echo ""
read -r -p "⚠️  Type 'yes' to confirm total deletion: " confirm < /dev/tty
if [[ "$confirm" != "yes" ]]; then
  log_warn "Teardown aborted by user."
  exit 0
fi

# 2. Delete
if [[ "$VM_UP" == "true" ]]; then
  log_step "[1/4] Deleting VM..."
  gcloud compute instances delete "$VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet > /dev/null
  log_info "VM removed."
else
  log_step "[1/4] Skipping VM..."
fi

if [[ "$DL_VM_UP" == "true" ]]; then
  log_step "[2/4] Deleting Downloader VM..."
  gcloud compute instances delete "$DL_VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet > /dev/null
  log_info "Downloader VM removed."
else
  log_step "[2/4] Skipping Downloader VM..."
fi

if [[ -n "$ALL_SNAPS" ]]; then
  log_step "[3/4] Deleting snapshots..."
  while IFS= read -r s; do
    gcloud compute snapshots delete "$s" --project="$PROJECT" --quiet > /dev/null
    log_info "Deleted '$s'."
  done <<< "$ALL_SNAPS"
fi

if [[ "$BUCKET_UP" == "true" ]]; then
  log_step "[4/4] Deleting GCS bucket..."
  gcloud storage rm --recursive "${BUCKET}/**" > /dev/null 2>&1 || true
  gcloud storage buckets delete "$BUCKET" --project="$PROJECT" > /dev/null
  log_info "Bucket removed."
fi

log_step "Teardown complete."
