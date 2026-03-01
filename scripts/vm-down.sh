#!/bin/bash
set -e

: "${1:?Usage: vm-down.sh <PROJECT> <BUCKET> <ZONE> <VM> <VM_USER> [SYNC_DIRS...]}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; VM_USER=${5:-$(whoami)}
# Grab the script's directory so we can call the other script reliably
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

trap 'echo ""; echo "❌ [1/2] Sync failed! VM is still running. Fix the issue and re-run: make down"' ERR

echo "📤 [1/2] Syncing to GCS..."
"$SCRIPT_DIR/vm-sync.sh" "$@"
echo "     ✅ Sync complete."

trap - ERR  # sync succeeded — clear trap so delete failure shows its own error
echo "🔥 [2/2] Destroying VM..."
gcloud compute instances delete "$VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet > /dev/null
echo "     ✅ VM destroyed."
echo ""
echo "✅ Done. No idle costs."