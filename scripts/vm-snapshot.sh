#!/bin/bash
set -e

: "${1:?Usage: vm-snapshot.sh <PROJECT> <ZONE> <VM> <SNAPSHOT>}"
PROJECT=$1; ZONE=$2; VM=$3; SNAP=$4

# Derive region from zone (e.g. europe-west2-b → europe-west2)
REGION="${ZONE%-*}"
SNAP_STAGING="${SNAP}-staging"

echo "📸 Creating Golden Snapshot (safe rotation)..."
# Phase 1: Create staging snapshot — old $SNAP is still intact if this fails
gcloud compute snapshots delete "$SNAP_STAGING" --project="$PROJECT" --quiet 2>/dev/null || true
gcloud compute snapshots create "$SNAP_STAGING" \
  --project="$PROJECT" \
  --source-disk="$VM" \
  --source-disk-zone="$ZONE" \
  --storage-location="$REGION"

# Phase 2: Promote — $SNAP_STAGING is our safety net while we swap the canonical name
gcloud compute snapshots delete "$SNAP" --project="$PROJECT" --quiet 2>/dev/null || true
gcloud compute snapshots create "$SNAP" \
  --project="$PROJECT" \
  --source-disk="$VM" \
  --source-disk-zone="$ZONE" \
  --storage-location="$REGION"

# Phase 3: Clean up staging
gcloud compute snapshots delete "$SNAP_STAGING" --project="$PROJECT" --quiet || true

echo "🧹 Destroying VM after snapshot..."
gcloud compute instances delete "$VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet

echo "✅ Golden snapshot saved. VM destroyed."