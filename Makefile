.PHONY: test

test:
	@test -d ../plenary.nvim || (echo "Missing test dependency: ../plenary.nvim"; exit 1)
	nvim --headless --noplugin -i NONE -u scripts/minimal_init.vim -c "PlenaryBustedDirectory tests/ { minimal_init = './scripts/minimal_init.vim' }" -c "qa"
