#!/bin/bash
set -e

: "${1:?Usage: vm-snapshot.sh <PROJECT> <ZONE> <VM> <SNAPSHOT_PREFIX>}"
PROJECT=$1; ZONE=$2; VM=$3; SNAP=$4

REGION="${ZONE%-*}"
KEEP=2
SNAP_NAME="${SNAP}-$(date +%Y%m%d-%H%M%S)"

echo "📸 [1/2] Creating snapshot '$SNAP_NAME'..."
gcloud compute snapshots create "$SNAP_NAME" \
  --project="$PROJECT" \
  --source-disk="$VM" \
  --source-disk-zone="$ZONE" \
  --storage-location="$REGION" > /dev/null
echo "     ✅ Done."

echo "🗑  Pruning (keeping last $KEEP)..."
OLD_SNAPS=$(gcloud compute snapshots list \
  --project="$PROJECT" \
  --filter="name~^${SNAP}-[0-9]" \
  --sort-by=~creationTimestamp \
  --format="value(name)" 2>/dev/null | tail -n +$((KEEP + 1)))

if [[ -n "$OLD_SNAPS" ]]; then
  while IFS= read -r old; do
    gcloud compute snapshots delete "$old" --project="$PROJECT" --quiet > /dev/null
    echo "     🗑  Deleted '$old'."
  done <<< "$OLD_SNAPS"
else
  echo "     ℹ️  Nothing to prune."
fi

echo ""
read -r -p "🧹 Destroy VM now? (y/N): " destroy < /dev/tty
if [[ "$destroy" =~ ^[Yy]$ ]]; then
  gcloud compute instances delete "$VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet > /dev/null
  echo "     ✅ VM destroyed. No idle costs."
else
  echo "     ℹ️  VM left running. Remember to run 'make down' when done."
fi
echo ""
echo "✅ Golden image saved."