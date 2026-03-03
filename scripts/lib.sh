#!/bin/bash

# Shared constants
SSH_FLAGS=("-o" "StrictHostKeyChecking=no" "-o" "UserKnownHostsFile=/dev/null")

# 1. Environment Loading
if [ -z "$PROJECT_ID" ]; then
  # SCRIPT_DIR is expected to be set by the caller
  TARGET_ENV="${ENV:-$SCRIPT_DIR/../.env}"
  if [[ -f "$TARGET_ENV" ]]; then
    export $(grep -v '^#' "$TARGET_ENV" | xargs)
  elif [[ -f "$SCRIPT_DIR/../$TARGET_ENV" ]]; then
    export $(grep -v '^#' "$SCRIPT_DIR/../$TARGET_ENV" | xargs)
  fi
fi

# 2. Defaults
: "${VM_NAME:=gpu-workspace}"
: "${VM_USER:=ubuntu}"
: "${SNAPSHOT:=gpu-golden-image}"
: "${MACHINE_TYPE:=g2-standard-4}"
: "${ACCELERATOR:=count=1,type=nvidia-l4}"
: "${DISK_SIZE:=50GB}"
: "${DOWNLOADER_MACHINE_TYPE:=e2-small}"

# Handle Downloader Mode naming suffix
if [[ "$IS_DOWNLOADER" == "true" && "$VM_NAME" != *"-downloader" ]]; then
  export VM_NAME="${VM_NAME}-downloader"
fi

# 3. Global Array Parsing
# Converts ".env" strings into Bash arrays for script consumption
IFS=' ' read -r -a SYNC_PAIRS <<< "$SYNC_DIRS"
IFS=' ' read -r -a FORWARDS <<< "$SSH_FORWARDS"

# 4. Validation Config
REQUIRED_VARS=(
  "PROJECT_ID"
  "BUCKET"
  "ZONE"
)

# 5. Derived Variables
REGION="${ZONE%-*}"

# 6. Validation Helpers
check_var() {
  local var_name=$1
  local value="${!var_name}"
  if [[ -z "$value" ]]; then
    log_error "Missing required variable: $var_name"
    echo "       Check your .env file or export it manually."
    exit 1
  fi
}

validate_config() {
  for var in "${REQUIRED_VARS[@]}"; do
    check_var "$var"
  done

  # Format checks
  if [[ ! "$BUCKET" == gs://* ]]; then
    log_error "Invalid BUCKET format: '$BUCKET'"
    echo "       It must start with 'gs://' (e.g., gs://my-gpu-bucket)"
    exit 1
  fi

  if [[ ! "$ZONE" =~ ^[a-z]+-[a-z]+[0-9]-[a-z]$ ]]; then
    log_warn "ZONE '$ZONE' doesn't look like a standard GCP zone (e.g., us-central1-a)."
    echo "       Proceeding, but check for typos if gcloud fails."
    echo "       Expected format: <region>-<zone> (e.g., us-central1-a)"
  fi

  # Dependency & Format Checks
  if ! command -v gcloud &> /dev/null; then
    log_error "'gcloud' CLI is not installed. Please install it to continue."
    exit 1
  fi

  if [[ "$PROJECT_ID" == "your-gcp-project-id" ]]; then
    log_error "PROJECT_ID is still 'your-gcp-project-id'. Please update your .env file."
    exit 1
  fi

  if [[ "$BUCKET" == "gs://your-gpu-vault-bucket" ]]; then
    log_error "BUCKET is still 'gs://your-gpu-vault-bucket'. Please update your .env file."
    exit 1
  fi
}

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
    [[ -z "$pair" ]] && continue
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

# Mount Logic (Downloader Mode)
# Usage: mount_dirs <BUCKET> <VM_USER> <VM_NAME> <ZONE> [SYNC_PAIRS...]
mount_dirs() {
  local bucket=$1; local user=$2; local vm=$3; local zone=$4
  shift 4
  local pairs=("$@")
  local bucket_name=${bucket#gs://}

  log_step "Mounting GCS folders (FUSE)..."

  ssh_cmd "$user" "$vm" "$zone" "command -v gcsfuse &> /dev/null" || {
    log_error "'gcsfuse' is not installed on the remote VM. Downloader mode requires it."
    exit 1
  }

  for pair in "${pairs[@]}"; do
    [[ -z "$pair" ]] && continue
    local local_path="${pair%%:*}"
    local remote_path="${pair#*:}"
    
    echo "     🔗  ${bucket}/${remote_path}/  ↔  ${local_path}"
    # We use --implicit-dirs so that gcsfuse sees directories even if there are no placeholder objects
    # We use --only-dir to mount a specific subfolder as the root of the mount point
    ssh_cmd "$user" "$vm" "$zone" "mkdir -p '${local_path}' && \
      gcsfuse --implicit-dirs --only-dir '${remote_path}' '${bucket_name}' '${local_path}'" > /dev/null
  done
}

unmount_dirs() {
  local user=$1; local vm=$2; local zone=$3
  shift 3
  local pairs=("$@")

  log_step "Unmounting GCS folders..."
  for pair in "${pairs[@]}"; do
    [[ -z "$pair" ]] && continue
    local local_path="${pair%%:*}"
    echo "     ⏏️  ${local_path}"
    ssh_cmd "$user" "$vm" "$zone" "fusermount -u '${local_path}' || true" > /dev/null
  done
}

# Auto-validate on load (unless SKIP_VAL is set)
if [[ -z "$SKIP_VALIDATION" ]]; then
  validate_config
fi
