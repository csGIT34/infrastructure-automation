# Terraform Testing Makefile
#
# Usage:
#   make test-modules              Run all module tests
#   make test-module MODULE=keyvault  Run specific module test
#   make test-patterns             Run all pattern tests
#   make test-pattern PATTERN=keyvault  Run specific pattern test
#   make test-all                  Run all tests
#   make test-cleanup              Clean orphaned test resources

SHELL := /bin/bash
.PHONY: test-modules test-module test-patterns test-pattern test-all test-cleanup help

# Colors for output
GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[0;33m
NC := \033[0m

# Directories
MODULES_DIR := modules
PATTERNS_DIR := patterns
SETUP_DIR := setup

# Get all module directories with tests
MODULE_TESTS := $(wildcard $(MODULES_DIR)/*/$(wildcard *.tftest.hcl))
PATTERN_TESTS := $(wildcard $(PATTERNS_DIR)/*/$(wildcard *.tftest.hcl))

help:
	@echo "Terraform Test Runner"
	@echo ""
	@echo "Usage:"
	@echo "  make test-modules              Run all module tests"
	@echo "  make test-module MODULE=name   Run specific module test"
	@echo "  make test-patterns             Run all pattern tests"
	@echo "  make test-pattern PATTERN=name Run specific pattern test"
	@echo "  make test-all                  Run all tests"
	@echo "  make test-cleanup              Clean orphaned test resources"
	@echo "  make list-modules              List available module tests"
	@echo "  make list-patterns             List available pattern tests"
	@echo ""
	@echo "Examples:"
	@echo "  make test-module MODULE=keyvault"
	@echo "  make test-pattern PATTERN=postgresql"

# Check prerequisites
check-prereqs:
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)Error: terraform not found$(NC)"; exit 1; }
	@terraform version | grep -q "Terraform v1\.[6-9]\|Terraform v[2-9]" || { echo "$(RED)Error: Terraform 1.6+ required for terraform test$(NC)"; exit 1; }
	@command -v az >/dev/null 2>&1 || { echo "$(RED)Error: az CLI not found$(NC)"; exit 1; }
	@az account show >/dev/null 2>&1 || { echo "$(RED)Error: Not logged into Azure. Run 'az login'$(NC)"; exit 1; }
	@echo "$(GREEN)Prerequisites OK$(NC)"

# Check for tfvars
check-config:
	@if [ ! -f "$(SETUP_DIR)/terraform.tfvars" ]; then \
		echo "$(RED)Error: setup/terraform.tfvars not found$(NC)"; \
		echo "Run: cp setup/terraform.tfvars.example setup/terraform.tfvars"; \
		echo "Then edit with your Azure subscription details"; \
		exit 1; \
	fi
	@echo "$(GREEN)Configuration OK$(NC)"

# List available tests
list-modules:
	@echo "Available module tests:"
	@for dir in $(MODULES_DIR)/*/; do \
		if [ -f "$$dir"*.tftest.hcl ]; then \
			echo "  - $$(basename $$dir)"; \
		fi; \
	done

list-patterns:
	@echo "Available pattern tests:"
	@for dir in $(PATTERNS_DIR)/*/; do \
		if [ -f "$$dir"*.tftest.hcl ]; then \
			echo "  - $$(basename $$dir)"; \
		fi; \
	done

# Run single module test
test-module: check-prereqs check-config
ifndef MODULE
	$(error MODULE is required. Usage: make test-module MODULE=keyvault)
endif
	@echo "$(YELLOW)Testing module: $(MODULE)$(NC)"
	@cd $(MODULES_DIR)/$(MODULE) && \
		terraform init -upgrade && \
		terraform test -var-file=../../$(SETUP_DIR)/terraform.tfvars
	@echo "$(GREEN)Module $(MODULE) tests passed$(NC)"

# Run all module tests
test-modules: check-prereqs check-config
	@echo "$(YELLOW)Running all module tests...$(NC)"
	@failed=0; \
	for dir in $(MODULES_DIR)/*/; do \
		module=$$(basename $$dir); \
		if ls "$$dir"*.tftest.hcl 1>/dev/null 2>&1; then \
			echo "$(YELLOW)Testing module: $$module$(NC)"; \
			cd "$$dir" && terraform init -upgrade >/dev/null && \
			if terraform test -var-file=../../$(SETUP_DIR)/terraform.tfvars; then \
				echo "$(GREEN)✓ $$module passed$(NC)"; \
			else \
				echo "$(RED)✗ $$module failed$(NC)"; \
				failed=1; \
			fi; \
			cd - >/dev/null; \
		fi; \
	done; \
	if [ $$failed -eq 1 ]; then \
		echo "$(RED)Some module tests failed$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)All module tests passed$(NC)"

# Run single pattern test
test-pattern: check-prereqs check-config
ifndef PATTERN
	$(error PATTERN is required. Usage: make test-pattern PATTERN=keyvault)
endif
	@echo "$(YELLOW)Testing pattern: $(PATTERN)$(NC)"
	@cd $(PATTERNS_DIR)/$(PATTERN) && \
		terraform init -upgrade && \
		terraform test -var-file=../../$(SETUP_DIR)/terraform.tfvars
	@echo "$(GREEN)Pattern $(PATTERN) tests passed$(NC)"

# Run all pattern tests
test-patterns: check-prereqs check-config
	@echo "$(YELLOW)Running all pattern tests...$(NC)"
	@failed=0; \
	for dir in $(PATTERNS_DIR)/*/; do \
		pattern=$$(basename $$dir); \
		if ls "$$dir"*.tftest.hcl 1>/dev/null 2>&1; then \
			echo "$(YELLOW)Testing pattern: $$pattern$(NC)"; \
			cd "$$dir" && terraform init -upgrade >/dev/null && \
			if terraform test -var-file=../../$(SETUP_DIR)/terraform.tfvars; then \
				echo "$(GREEN)✓ $$pattern passed$(NC)"; \
			else \
				echo "$(RED)✗ $$pattern failed$(NC)"; \
				failed=1; \
			fi; \
			cd - >/dev/null; \
		fi; \
	done; \
	if [ $$failed -eq 1 ]; then \
		echo "$(RED)Some pattern tests failed$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)All pattern tests passed$(NC)"

# Run all tests
test-all: test-modules test-patterns
	@echo "$(GREEN)All tests completed$(NC)"

# Cleanup orphaned test resources
test-cleanup:
	@echo "$(YELLOW)Finding orphaned test resource groups...$(NC)"
	@groups=$$(az group list --query "[?starts_with(name, 'rg-tftest-')].name" -o tsv); \
	if [ -z "$$groups" ]; then \
		echo "$(GREEN)No orphaned test resource groups found$(NC)"; \
	else \
		echo "Found orphaned groups:"; \
		echo "$$groups"; \
		read -p "Delete all? (y/N) " confirm; \
		if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
			for group in $$groups; do \
				echo "Deleting $$group..."; \
				az group delete --name "$$group" --yes --no-wait; \
			done; \
			echo "$(GREEN)Cleanup initiated (resources deleting in background)$(NC)"; \
		else \
			echo "Cleanup cancelled"; \
		fi; \
	fi

# Quick sanity check - just naming module (no Azure resources)
test-quick: check-prereqs
	@echo "$(YELLOW)Running quick sanity check (naming module only)...$(NC)"
	@cd $(MODULES_DIR)/naming && \
		terraform init -upgrade >/dev/null && \
		terraform test
	@echo "$(GREEN)Quick test passed$(NC)"
