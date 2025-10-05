local ts = require("autotag.ts")
local Config = require("autotag.config")

local M = {}

local void_elements = {
  "area",
  "base",
  "br",
  "col",
  "embed",
  "hr",
  "img",
  "input",
  "link",
  "meta",
  "param",
  "source",
  "track",
  "wbr"
}

---@param bufnr integer
local function maybe_close_tag(bufnr)
  if bufnr ~= vim.api.nvim_get_current_buf() then
    return
  end

  local aliased_lang = ts.get_aliased_lang(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, aliased_lang)
  if not ok or not parser then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)

  -- refresh ts state / parse only current line
  local cursor_row = cursor[1] - 1
  local trees = parser:parse({ cursor_row, cursor_row })
  if not trees or vim.tbl_isempty(trees) then
    return
  end

  -- get node at cursor position with col - 1, so we are inside the written tag
  local opening_node = ts.get_opening_node({ bufnr = bufnr, pos = { cursor[1] - 1, cursor[2] - 1 } }, 0)
  if not opening_node then
    return
  end

  -- get id and tag name
  local opening_node_identifier = ts.get_node_identifier(opening_node)
  local tag_name = opening_node_identifier and vim.treesitter.get_node_text(opening_node_identifier, bufnr) or ""

  if tag_name == "" then
    return
  end

  -- do not close void elements
  if vim.list_contains(void_elements, tag_name) then
    return
  end

  -- check if next char is "/" or ">" "<div|></div>"
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  local char_after_cursor = line:sub(cursor[2] + 1, cursor[2] + 1)
  if char_after_cursor == "/" or char_after_cursor == ">" then
    return
  end

  -- insert closing tag
  local closing_tag = string.format("</%s>", tag_name)
  vim.api.nvim_put({ closing_tag }, "", false, false)
  vim.api.nvim_win_set_cursor(win, cursor)
end

---@param namespace_id integer
local function detach_listener(namespace_id)
  vim.on_key(nil, namespace_id)
end

---@param bufnr integer
---@param namespace_id integer
local function attach_listener(bufnr, namespace_id)
  vim.on_key(function(_, typed)
    local current_buf = vim.api.nvim_get_current_buf()

    if Config.options.disable_in_macro and vim.fn.reg_recording() ~= "" then
      return
    end

    if bufnr ~= current_buf or typed ~= ">" or vim.api.nvim_get_mode().mode ~= "i" then
      return
    end

    vim.schedule(function()
      maybe_close_tag(bufnr)
    end)
  end, namespace_id)
end

---@param bufnr integer
function M.init(bufnr)
  local group_key = string.format("autotag/close-tag-%d", bufnr)
  local augroup = vim.api.nvim_create_augroup(group_key, {})
  local namespace_id = vim.api.nvim_create_namespace(group_key)

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      detach_listener(namespace_id)
      attach_listener(bufnr, namespace_id)
    end
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      detach_listener(namespace_id)
    end
  })
end

return M
