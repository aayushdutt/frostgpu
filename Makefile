# User configuration — copy config.mk.example to config.mk and fill in your values.
-include config.mk

.PHONY: init up down snapshot ssh ui

init:
	@chmod +x scripts/*.sh
	@./scripts/infra-init.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME)

up:
	@./scripts/vm-up.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(SNAPSHOT) $(VM_USER)

down:
	@./scripts/vm-down.sh $(PROJECT_ID) $(BUCKET) $(ZONE) $(VM_NAME) $(VM_USER)

snapshot:
	@./scripts/vm-snapshot.sh $(PROJECT_ID) $(ZONE) $(VM_NAME) $(SNAPSHOT)

ui:
	@gcloud compute ssh $(VM_USER)@$(VM_NAME) --zone=$(ZONE) --ssh-flag="-L 7860:localhost:7860" --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null"

ssh:
	@gcloud compute ssh $(VM_USER)@$(VM_NAME) --zone=$(ZONE) --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null"