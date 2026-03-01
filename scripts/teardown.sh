#!/bin/bash
set -e

: "${1:?Usage: teardown.sh <PROJECT> <BUCKET> <ZONE> <VM> <SNAPSHOT>}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; SNAP=$5

echo "🔍 Scanning GCP resources..."
echo ""

# Resolve actual resources before prompting
VM_EXISTS=false
if gcloud compute instances describe "$VM" --project="$PROJECT" --zone="$ZONE" > /dev/null 2>&1; then
  VM_EXISTS=true
fi

ALL_SNAPS=$(gcloud compute snapshots list \
  --project="$PROJECT" \
  --filter="name~^${SNAP}" \
  --format="value(name)" 2>/dev/null)

BUCKET_EXISTS=false
if gcloud storage buckets describe "$BUCKET" --project="$PROJECT" > /dev/null 2>&1; then
  BUCKET_EXISTS=true
fi

# Show exactly what will be deleted
echo "⚠️  The following resources will be permanently deleted:"
echo ""

if $VM_EXISTS; then
  echo "   🖥  VM:        $VM ($ZONE)"
else
  echo "   🖥  VM:        (not found)"
fi

if [[ -n "$ALL_SNAPS" ]]; then
  while IFS= read -r s; do
    echo "   📸 Snapshot:  $s"
  done <<< "$ALL_SNAPS"
else
  echo "   📸 Snapshots: (none found)"
fi

if $BUCKET_EXISTS; then
  echo "   🪣 Bucket:    $BUCKET (ALL contents)"
else
  echo "   🪣 Bucket:    (not found)"
fi

echo ""
read -r -p "Type 'yes' to confirm: " confirm < /dev/tty
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi
echo ""

if $VM_EXISTS; then
  echo "🗑  [1/3] Deleting VM..."
  gcloud compute instances delete "$VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet > /dev/null
  echo "     ✅ VM deleted."
else
  echo "🗑  [1/3] VM not found, skipping."
fi

echo "🗑  [2/3] Deleting snapshots..."
if [[ -n "$ALL_SNAPS" ]]; then
  while IFS= read -r s; do
    gcloud compute snapshots delete "$s" --project="$PROJECT" --quiet > /dev/null
    echo "     ✅ '$s' deleted."
  done <<< "$ALL_SNAPS"
else
  echo "     ℹ️  No snapshots found, skipping."
fi

echo "🗑  [3/3] Deleting GCS bucket..."
if $BUCKET_EXISTS; then
  gcloud storage rm --recursive "${BUCKET}/**" > /dev/null 2>&1 || true
  gcloud storage buckets delete "$BUCKET" --project="$PROJECT" > /dev/null
  echo "     ✅ Bucket deleted."
else
  echo "     ℹ️  Bucket not found, skipping."
fi

echo ""
echo "✅ Teardown complete. All GCP resources removed."
