# Makefile for Me Protocol Solidity Project
# ==========================================

# Default target
.DEFAULT_GOAL := help

# Variables
FORGE_FLAGS :=
GAS_REPORT_FLAGS := --gas-report
COVERAGE_FLAGS := --coverage
V := -vv
PROJECT_NAME := DSC-ENGINE

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Help target - displays available commands
.PHONY: help
help: ## Display this help message
	@echo "$(GREEN) $(PROJECT_NAME) Commands$(NC)"
	@echo "=================================="
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "$(YELLOW)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Installation commands
.PHONY: install
install: ## Install all dependencies (Forge + Node.js)
	@echo "$(GREEN)Installing Forge dependencies...$(NC)"
	@forge install OpenZeppelin/openzeppelin-contracts@v4.9.0 
	@forge install foundry-rs/forge-std 
	@echo "$(GREEN)Installing Node.js dependencies...$(NC)"
	@yarn install
	@echo "$(GREEN)All dependencies installed successfully!$(NC)"

.PHONY: install-forge
install-forge: ## Install only Forge dependencies
	@echo "$(GREEN)Installing Forge dependencies...$(NC)"
	@forge install OpenZeppelin/openzeppelin-contracts@v4.9.0 
	@forge install foundry-rs/forge-std
	@echo "$(GREEN)Forge dependencies installed!$(NC)"

.PHONY: install-node
install-node: ## Install only Node.js dependencies
	@echo "$(GREEN)Installing Node.js dependencies...$(NC)"
	@yarn install
	@echo "$(GREEN)Node.js dependencies installed!$(NC)"

# Build commands
.PHONY: build
build: ## Compile the smart contracts
	@echo "$(GREEN)Building contracts...$(NC)"
	@forge build

.PHONY: clean
clean: ## Clean build artifacts
	@echo "$(GREEN)Cleaning build artifacts...$(NC)"
	@forge clean

.PHONY: rebuild
rebuild: clean build ## Clean and rebuild contracts

# Testing commands
.PHONY: test
test: ## Run all tests
	@echo "$(GREEN)Running tests...$(NC)"
	@forge test $(FORGE_FLAGS)

.PHONY: test-gas
test-gas: ## Run tests with gas reporting
	@echo "$(GREEN)Running tests with gas reporting...$(NC)"
	@forge test $(FORGE_FLAGS) $(GAS_REPORT_FLAGS)

.PHONY: test-coverage
test-coverage: ## Run tests with coverage reporting
	@echo "$(GREEN)Running tests with coverage...$(NC)"
	@forge coverage $(FORGE_FLAGS)

.PHONY: test-verbose
test-verbose: ## Run tests with verbose output
	@echo "$(GREEN)Running tests with verbose output...$(NC)"
	@forge test $(FORGE_FLAGS) -vvv

.PHONY: test-specific
test-specific: ## Run specific test file (usage: make test-specific FILE=path/to/test.sol)
	@echo "$(GREEN)Running specific test: $(FILE)$(NC)"
	@forge test $(FORGE_FLAGS) --match-path $(FILE)


.PHONY: test-func
test-func: ## Run specific test function (usage: make test-func NAME=testFunctionName [V=-v])
	@echo "$(GREEN)Running test: $(NAME) with verbosity: $(V)$(NC)"
	@forge test $(FORGE_FLAGS) --mt $(NAME) $(V)

# Formatting and linting
.PHONY: format
format: ## Format Solidity code
	@echo "$(GREEN)Formatting Solidity code...$(NC)"
	@forge fmt

.PHONY: format-check
format-check: ## Check if code is properly formatted
	@echo "$(GREEN)Checking code formatting...$(NC)"
	@forge fmt --check

# Deployment commands
.PHONY: deploy-local
deploy-local: ## Deploy to local network
	@echo "$(GREEN)Deploying to local network...$(NC)"
	@forge script script/deploy-protocol.sol --rpc-url http://localhost:8545 --broadcast

.PHONY: deploy-sepolia
deploy-sepolia: ## Deploy to Sepolia testnet
	@echo "$(GREEN)Deploying to Sepolia...$(NC)"
	@forge script script/deploy-protocol.sol --rpc-url $(SEPOLIA_RPC_URL) --broadcast --verify

# Utility commands
.PHONY: size
size: ## Check contract sizes
	@echo "$(GREEN)Checking contract sizes...$(NC)"
	@forge build --sizes

.PHONY: tree
tree: ## Display dependency tree
	@echo "$(GREEN)Dependency tree:$(NC)"
	@forge tree

.PHONY: remappings
remappings: ## Display remappings
	@echo "$(GREEN)Current remappings:$(NC)"
	@forge remappings

.PHONY: remappings-txt
remappings-txt: ## Write remappings to file
	@echo "$(GREEN)Writing remappings to file:$(NC)"
	@forge remappings > remappings.txt

.PHONY: update
update: ## Update dependencies
	@echo "$(GREEN)Updating Forge dependencies...$(NC)"
	@forge update
	@echo "$(GREEN)Updating Node.js dependencies...$(NC)"
	@yarn upgrade

# Development environment
.PHONY: anvil
anvil: ## Start local Anvil node
	@echo "$(GREEN)Starting Anvil local node...$(NC)"
	@anvil

.PHONY: console
console: ## Start Forge console
	@echo "$(GREEN)Starting Forge console...$(NC)"
	@forge console

# Git hooks and setup
.PHONY: setup-hooks
setup-hooks: ## Setup git hooks for development
	@echo "$(GREEN)Setting up git hooks...$(NC)"
	@echo "#!/bin/sh\nmake format-check && make test" > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "$(GREEN)Git hooks setup complete!$(NC)"

# Documentation
.PHONY: docs
docs: ## Generate documentation
	@echo "$(GREEN)Generating documentation...$(NC)"
	@forge doc

.PHONY: docs-serve
docs-serve: ## Serve documentation locally
	@echo "$(GREEN)Serving documentation...$(NC)"
	@forge doc --serve

# Security and analysis
.PHONY: slither
slither: ## Run Slither static analysis (requires slither-analyzer)
	@echo "$(GREEN)Running Slither analysis...$(NC)"
	@slither .

.PHONY: mythril
mythril: ## Run Mythril security analysis (requires mythril)
	@echo "$(GREEN)Running Mythril analysis...$(NC)"
	@myth analyze contracts/

# Environment validation
.PHONY: check-env
check-env: ## Check if required environment variables are set
	@echo "$(GREEN)Checking environment variables...$(NC)"
	@if [ -z "$(PRIVATE_KEY)" ]; then echo "$(RED)Warning: PRIVATE_KEY not set$(NC)"; fi
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then echo "$(RED)Warning: SEPOLIA_RPC_URL not set$(NC)"; fi
	@if [ -z "$(ETHERSCAN_API_KEY)" ]; then echo "$(RED)Warning: ETHERSCAN_API_KEY not set$(NC)"; fi
	@echo "$(GREEN)Environment check complete$(NC)"

# Complete setup for new developers
.PHONY: setup
setup: install format build test ## Complete setup for new developers
	@echo "$(GREEN)Setup complete! Project is ready for development.$(NC)"
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Copy .env.example to .env and fill in your values"
	@echo "  2. Run 'make check-env' to verify environment variables"
	@echo "  3. Run 'make test' to ensure everything is working"

# Quick development cycle
.PHONY: dev
dev: format build test ## Quick development cycle: format, build, test
	@echo "$(GREEN)Development cycle complete!$(NC)"

# CI/CD targets
.PHONY: ci
ci: install format-check build test-coverage ## CI pipeline: install, check format, build, test with coverage
	@echo "$(GREEN)CI pipeline completed successfully!$(NC)"
