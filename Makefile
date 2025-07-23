# TODO: also add the package to the .rockspec file
.PHONY: add
add: ## Add a lua dependency to the local project, usage: make add package=package-name
	luarocks install --tree lua_modules $(package)

.PHONY: install
install: ## Install project dependencies
	luarocks install --tree lua_modules --deps-only zet-dev-1.rockspec

.PHONY: run
run: ## Run the zet application
	@source $(CURDIR)/project.env && love ./src/

.PHONY: lint
lint: ## Lint lua source files
	@luacheck src/

.PHONY: format
format: ## Format lua source files
	@stylua -v src/

.PHONY: docs
docs: ## Generate documentation
	@./lua_modules/bin/ldoc src/

.PHONY: help
help: ## Show this help
	@grep -E '^[a-z.A-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
