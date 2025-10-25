# Run all test files
test:
	nvim --headless --noplugin -u ./scripts/minimal-init.lua -c "lua MiniTest.run()"

# Run test from file at `$FILE` environment variable
test-file:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Download dependencies
install:
	@mkdir -p deps
	git clone --depth=1 --single-branch --filter=blob:none --branch=main --quiet https://github.com/nvim-mini/mini.test.git deps/mini.test
	git clone --depth=1 --single-branch --filter=blob:none --branch=main --quiet https://github.com/nvim-treesitter/nvim-treesitter.git deps/nvim-treesitter
