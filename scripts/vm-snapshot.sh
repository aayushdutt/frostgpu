#!/bin/bash
set -e

: "${1:?Usage: vm-snapshot.sh <PROJECT> <BUCKET> <ZONE> <VM> <SNAPSHOT_PREFIX> <VM_USER> [SYNC_DIRS...]}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; SNAP=$5; VM_USER=${6:-$(whoami)}
shift 6
SYNC_PAIRS=("$@")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${ZONE%-*}"
KEEP=2
SNAP_NAME="${SNAP}-$(date +%Y%m%d-%H%M%S)"

ssh_cmd() {
  gcloud compute ssh "${VM_USER}@${VM}" --zone="$ZONE" \
    --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null" \
    --command="$1"
}

# ── Pre-flight check ──────────────────────────────────────────────────────────
echo ""
echo "🚀 Snapshotting '$VM' as '$SNAP_NAME'..."

if [[ ${#SYNC_PAIRS[@]} -gt 0 ]]; then
  echo ""
  echo "📦 SYNC & CLEAN?"
  echo "   (This syncs to GCS, empties local folders, then snapshots for a lean golden image)"
  read -r -p "   Proceed with auto-sync and deep clean? (y/N): " autopre < /dev/tty
  if [[ "$autopre" =~ ^[Yy]$ ]]; then
    echo "📤 Syncing to GCS..."
    "$SCRIPT_DIR/vm-sync.sh" "$PROJECT" "$BUCKET" "$ZONE" "$VM" "$VM_USER" "${SYNC_PAIRS[@]}"
    
    for pair in "${SYNC_PAIRS[@]}"; do
      LOCAL="${pair%%:*}"
      echo "     🧹 Emptying ${LOCAL}..."
      ssh_cmd "rm -rf '${LOCAL}'/*" || echo "     ⚠️  Failed to empty ${LOCAL}."
    done
    echo "     ✅ Sync & Clean complete."
  else
    echo "     ⚠️  Skipping sync/clean. Warning: Snapshot will include local data (higher cost)."
    read -r -p "   Continue with snapshot anyway? (y/N): " proceed < /dev/tty
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi
fi

echo ""

# ── Create snapshot ───────────────────────────────────────────────────────────
echo "📸 [1/2] Creating snapshot..."
gcloud compute snapshots create "$SNAP_NAME" \
  --project="$PROJECT" \
  --source-disk="$VM" \
  --source-disk-zone="$ZONE" \
  --storage-location="$REGION" > /dev/null
echo "     ✅ Done."

# ── Prune old snapshots ───────────────────────────────────────────────────────
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