.PHONY: test deps

PLENARY_DIR ?= .deps/plenary.nvim

test: deps
	nvim --headless --noplugin -i NONE -u scripts/minimal_init.vim -c "PlenaryBustedDirectory tests/ { minimal_init = './scripts/minimal_init.vim' }" -c "qa"

deps: $(PLENARY_DIR)

$(PLENARY_DIR):
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim.git $(PLENARY_DIR)
