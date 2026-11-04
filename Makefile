.DEFAULT_GOAL := help

INSTALL_DIR ?= $(HOME)/Applications
OPEN_APP ?= 1

.PHONY: help build install run test-install

help:
	@echo "make install       Build, install to ~/Applications, and launch"
	@echo "make build         Build the app in .build/Cove.app"
	@echo "make run           Open the installed app"
	@echo "make test-install  Test installation and updates in a temporary directory"
	@echo ""
	@echo 'Options: INSTALL_DIR="/custom/path" OPEN_APP=0'

build:
	@python3 build-and-run.py --build-only

install: build
	@INSTALL_DIR="$(INSTALL_DIR)" OPEN_APP="$(OPEN_APP)" bash scripts/install-app.sh

run:
	@open "$(INSTALL_DIR)/Cove.app"

test-install: build
	@bash scripts/test-install.sh
