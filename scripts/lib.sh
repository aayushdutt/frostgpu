#!/bin/bash

# Shared constants
SSH_FLAGS=("-o" "StrictHostKeyChecking=no" "-o" "UserKnownHostsFile=/dev/null")

# Load configuration if environment file exists
# This allows scripts to be run directly with ENV_FILE=.env.l4
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  # Source without comments and handle exports
  export $(grep -v '^#' "$ENV_FILE" | xargs)
elif [ -f "$SCRIPT_DIR/../.env" ]; then
  # Fallback to default .env if no ENV_FILE is provided
  export $(grep -v '^#' "$SCRIPT_DIR/../.env" | xargs)
fi

# Logging helpers
log_info()    { echo -e "     ✅ \033[0;32m$1\033[0m"; }
log_warn()    { echo -e "     ⚠️  \033[0;33m$1\033[0m"; }
log_error()   { echo -e "     ❌ \033[0;31m$1\033[0m"; }
log_step()    { echo -e "\n\033[1;34m$1\033[0m"; }

# Centralized SSH executor
ssh_cmd() {
  local user=$1
  local vm=$2
  local zone=$3
  local cmd=$4
  gcloud compute ssh "${user}@${vm}" --zone="${zone}" \
    "${SSH_FLAGS[@]/#/--ssh-flag=}" \
    --command="${cmd}"
}

# Resource checking
vm_exists() {
  local project=$1; local zone=$2; local vm=$3
  gcloud compute instances describe "$vm" --project="$project" --zone="$zone" > /dev/null 2>&1
}

bucket_exists() {
  local project=$1; local bucket=$2
  gcloud storage buckets describe "$bucket" --project="$project" > /dev/null 2>&1
}

# Data Syncing Logic
# Usage: sync_dirs <DIRECTION: up|down> <BUCKET> <VM_USER> <VM_NAME> <ZONE> [SYNC_PAIRS...]
sync_dirs() {
  local direction=$1; local bucket=$2; local user=$3; local vm=$4; local zone=$5
  shift 5
  local pairs=("$@")

  if [[ ${#pairs[@]} -eq 0 ]]; then
    log_warn "No SYNC_DIRS configured — skipping GCS sync."
    return
  fi

  for pair in "${pairs[@]}"; do
    local local_path="${pair%%:*}"
    local remote_path="${pair#*:}"
    
    if [[ "$direction" == "up" ]]; then
      # Pull: GCS -> VM
      echo "     ↓  ${bucket}/${remote_path}/  →  ${local_path}"
      ssh_cmd "$user" "$vm" "$zone" "mkdir -p '${local_path}' && \
        (gcloud storage ls '${bucket}/${remote_path}/' > /dev/null 2>&1 \
          && gcloud storage rsync '${bucket}/${remote_path}/' '${local_path}/' --recursive \
          || echo 'No data at ${bucket}/${remote_path}/ yet, skipping.')" > /dev/null
    else
      # Push: VM -> GCS
      echo "     ↑  ${local_path}  →  ${bucket}/${remote_path}/"
      ssh_cmd "$user" "$vm" "$zone" "gcloud storage rsync '${local_path}/' '${bucket}/${remote_path}/' --recursive" > /dev/null
    fi
  done
}
