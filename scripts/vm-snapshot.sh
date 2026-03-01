#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${1:?Usage: vm-snapshot.sh <PROJECT> <BUCKET> <ZONE> <VM> <SNAPSHOT_PREFIX> <VM_USER> [SYNC_DIRS...]}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; SNAP=$5; VM_USER=${6:-$(whoami)}
shift 6
SYNC_PAIRS=("$@")

KEEP=2
SNAP_NAME="${SNAP}-$(date +%Y%m%d-%H%M%S)"
REGION="${ZONE%-*}"

log_step "Preparing snapshot for '$VM'..."

if [[ ${#SYNC_PAIRS[@]} -gt 0 ]]; then
  echo ""
  echo "📦 SYNC & CLEAN?"
  echo "   (This syncs to GCS, empties local folders, then snapshots for a lean golden image)"
  read -r -p "   Proceed with auto-sync and deep clean? (y/N): " autopre < /dev/tty
  if [[ "$autopre" =~ ^[Yy]$ ]]; then
    log_step "Syncing to GCS..."
    sync_dirs "down" "$BUCKET" "$VM_USER" "$VM" "$ZONE" "${SYNC_PAIRS[@]}"
    
    for pair in "${SYNC_PAIRS[@]}"; do
      LOCAL="${pair%%:*}"
      log_warn "Emptying ${LOCAL}..."
      ssh_cmd "$VM_USER" "$VM" "$ZONE" "rm -rf '${LOCAL}'/*" || log_warn "Failed to empty ${LOCAL}."
    done
    log_info "Sync & Clean complete."
  else
    log_warn "Skipping sync/clean. Snapshot will include local data (higher storage cost)."
    read -r -p "   Continue with snapshot anyway? (y/N): " proceed < /dev/tty
    [[ ! "$proceed" =~ ^[Yy]$ ]] && echo "Aborted." && exit 0
  fi
fi

log_step "Creating snapshot '$SNAP_NAME'..."
gcloud compute snapshots create "$SNAP_NAME" \
  --project="$PROJECT" --source-disk="$VM" --source-disk-zone="$ZONE" \
  --storage-location="$REGION" > /dev/null
log_info "Snapshot created."

log_step "Pruning old snapshots (keeping last $KEEP)..."
OLD_SNAPS=$(gcloud compute snapshots list \
  --project="$PROJECT" --filter="name~^${SNAP}-[0-9]" \
  --sort-by=~creationTimestamp --format="value(name)" 2>/dev/null | tail -n +$((KEEP + 1)))

if [[ -n "$OLD_SNAPS" ]]; then
  while IFS= read -r old; do
    gcloud compute snapshots delete "$old" --project="$PROJECT" --quiet > /dev/null
    log_info "Deleted old snapshot '$old'."
  done <<< "$OLD_SNAPS"
else
  log_info "Nothing to prune."
fi

echo ""
read -r -p "🧹 Destroy VM now? (y/N): " destroy < /dev/tty
if [[ "$destroy" =~ ^[Yy]$ ]]; then
  gcloud compute instances delete "$VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet > /dev/null
  log_info "VM destroyed. No idle costs."
fi

log_info "Golden image saved successfully."