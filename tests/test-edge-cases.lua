local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal-init.lua" })
      child.lua([[AC = require("autotag.close-tag")]])
      child.lua([[AR = require("autotag.rename-tag")]])
    end,
    post_once = child.stop
  },
})

---@return integer
local function bufnr()
  return child.api.nvim_get_current_buf()
end

---@return integer
local function winnr()
  return child.api.nvim_get_current_win()
end

T["close-tag-unsupported-filetype"] = function()
  local buf = bufnr()

  child.bo.readonly = false
  child.bo.filetype = "text" -- not supported filetype
  child.lua_func(function(buf) AC.init(buf) end, buf)
  child.cmd("doautocmd BufEnter")

  child.cmd("startinsert!")
  child.type_keys("<", "div", ">")

  local result = child.api.nvim_buf_get_lines(buf, 0, -1, true)
  expect.equality(result, { "<div>" }) -- should not close on not supported filetype
end

T["rename-tag-unsupported-filetype"] = function()
  local buf = bufnr()
  local win = winnr()

  child.bo.readonly = false
  child.bo.filetype = "text" -- not supported filetype
  child.lua_func(function(buf) AR.init(buf) end, buf)
  child.cmd("doautocmd BufEnter")

  child.api.nvim_buf_set_lines(buf, 0, -1, true, { "<div></div>" })
  child.api.nvim_win_set_cursor(win, { 1, 1 })

  child.type_keys("ciw")
  child.type_keys("main")

  local result = child.api.nvim_buf_get_lines(buf, 0, -1, true)
  expect.equality(result, { "<main></div>" }) -- should not close on not supported filetype
end

return T
