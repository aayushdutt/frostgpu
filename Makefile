# Ensure scripts are executable on every run
_ := $(shell chmod +x scripts/*.sh)

# Configuration
# ==============================================================================
# To switch environments, change this variable to point to your desired file
# (e.g., .env for L4/Seoul, .env.t4 for T4/London).
#
# You can also override it via CLI: make up ENV=.env.t4
# ==============================================================================
ENV ?= .env
-include $(ENV)
export

.PHONY: init up down sync snapshot ssh tunnel teardown stop vm-stop dl-up dl-down dl-stop dl-sync dl-ssh

# Dynamic target VM name based on goal prefix
TARGET_VM = $(VM_NAME)

dl-%: TARGET_VM = $(VM_NAME)-downloader

init:
	@chmod +x scripts/*.sh
	@./scripts/infra-init.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(VM_USER)

up dl-up:
	@./scripts/vm-up.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(TARGET_VM) $(SNAPSHOT) $(VM_USER) $(SYNC_DIRS)

down dl-down:
	@./scripts/vm-down.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(TARGET_VM) $(VM_USER) $(SYNC_DIRS)

stop dl-stop vm-stop:
	@./scripts/vm-stop.sh $(PROJECT_ID) $(ZONE) $(TARGET_VM)

sync dl-sync:
	@./scripts/vm-sync.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(TARGET_VM) $(VM_USER) $(SYNC_DIRS)

ssh dl-ssh:
	@gcloud compute ssh $(VM_USER)@$(TARGET_VM) --zone=$(ZONE) --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null"

tunnel:
	@./scripts/vm-tunnel.sh $(VM_USER) $(VM_NAME) $(ZONE) $(SSH_FORWARDS)

snapshot:
	@./scripts/vm-snapshot.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(SNAPSHOT) $(VM_USER) $(SYNC_DIRS)

teardown:
	@./scripts/teardown.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(SNAPSHOT)