-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.opt.runtimepath:append(vim.fn.getcwd())

-- Set up 'mini.test'
local function setup_mini_test()
  -- Add 'mini.test' to runtimepath
  vim.opt.runtimepath:append("deps/mini.test")
  local MiniTest = require("mini.test")

  MiniTest.setup({
    collect = {
      find_files = function()
        return vim.fn.globpath("tests", "**/test-*.lua", true, true)
      end
    },
    execute = {
      reporter = MiniTest.gen_reporter.stdout({
        group_depth = 2
      })
    },
    script_path = "scripts/mini-test.lua",
  })
end

-- setup treesitter
local function setup_tree_sitter()
  -- Add treesitter to runtimepath
  -- Add parser directory to runtimepath
  vim.opt.runtimepath:append("deps/nvim-treesitter")
  vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site")

  local parsers = {
    "xml",
    "html",
    "razor",
    "angular"
  }

  require("nvim-treesitter").setup()
  require("nvim-treesitter").install(parsers, { summary = true }):wait(1 * 60 * 1000) -- 1 minute
end

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  setup_mini_test()
  setup_tree_sitter()
end
