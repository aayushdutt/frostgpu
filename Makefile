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

init:
	@chmod +x scripts/*.sh
	@./scripts/infra-init.sh

up:
	@./scripts/vm-up.sh

dl-up:
	@IS_DOWNLOADER=true ./scripts/vm-up.sh

down:
	@./scripts/vm-down.sh

dl-down:
	@IS_DOWNLOADER=true ./scripts/vm-down.sh

stop vm-stop:
	@./scripts/vm-stop.sh

dl-stop:
	@IS_DOWNLOADER=true ./scripts/vm-stop.sh

sync:
	@./scripts/vm-sync.sh

dl-sync:
	@IS_DOWNLOADER=true ./scripts/vm-sync.sh

ssh:
	@./scripts/vm-ssh.sh

dl-ssh:
	@IS_DOWNLOADER=true ./scripts/vm-ssh.sh

tunnel:
	@./scripts/vm-tunnel.sh

snapshot:
	@./scripts/vm-snapshot.sh

teardown:
	@./scripts/teardown.sh
