# Ensure scripts are executable on every run
_ := $(shell chmod +x scripts/*.sh)

# User configuration — copy config.mk.example to config.mk and fill in your values.
-include config.mk

# Export variables to sub-shells so scripts can access them directly
# (Reduces noise in the target definitions)
export PROJECT_ID BUCKET ZONE VM_NAME SNAPSHOT VM_USER SYNC_DIRS SSH_FORWARDS MACHINE_TYPE ACCELERATOR

.PHONY: init up down sync snapshot ssh tunnel teardown

init:
	@chmod +x scripts/*.sh
	@./scripts/infra-init.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(VM_USER)

up:
	@./scripts/vm-up.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(SNAPSHOT) $(VM_USER) $(SYNC_DIRS)

down:
	@./scripts/vm-down.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(VM_USER) $(SYNC_DIRS)

sync:
	@./scripts/vm-sync.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(VM_USER) $(SYNC_DIRS)

snapshot:
	@./scripts/vm-snapshot.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(SNAPSHOT) $(VM_USER) $(SYNC_DIRS)

tunnel:
	@./scripts/vm-tunnel.sh $(VM_USER) $(VM_NAME) $(ZONE) $(SSH_FORWARDS)

ssh:
	@gcloud compute ssh $(VM_USER)@$(VM_NAME) --zone=$(ZONE) --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null"

teardown:
	@./scripts/teardown.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(SNAPSHOT)