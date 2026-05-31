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

---@param line string
---@param col integer
---@return string?
local function detect_tag_name_from_line(line, col)
  -- We are only called right after the user typed ">"; cursor is sitting
  -- just after that ">". Look at the portion of the line up to the cursor.
  local pre = line:sub(1, col)
  if pre:sub(-1) ~= ">" then
    return
  end

  -- Find the start index of the most recent "<...>" segment that ends
  -- right at the cursor. We disallow nested "<" or ">" inside.
  local start_idx = pre:match("()<[^<>]*>$")
  if not start_idx then
    return
  end

  local segment = pre:sub(start_idx)

  -- Skip self-closing "<tag ... />"
  if segment:match("/>$") then
    return
  end

  -- Skip closing tag "</tag>"
  if segment:sub(2, 2) == "/" then
    return
  end

  -- Skip "<!doctype ...>", comments, processing instructions, etc.
  local first = segment:sub(2, 2)
  if first == "!" or first == "?" then
    return
  end

  -- Extract the tag name. Allow standard HTML/XML name characters
  -- (letters, digits, dashes, underscores, dots, colons).
  local tag_name = segment:match("^<([%a_][%w%-_:%.]*)")
  return tag_name
end

---@param bufnr integer
local function maybe_close_tag(bufnr)
  if bufnr ~= vim.api.nvim_get_current_buf() then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return
  end

  local tag_name

  -- Try treesitter detection first. In files where the parser handles
  -- the surrounding context well, this gives us the most accurate node.
  local aliased_lang = ts.get_aliased_lang(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, aliased_lang)
  if not ok or not parser then
    -- No parser available for this buffer: this is an unsupported
    -- filetype - do nothing (don't even fall back to the regex path).
    return
  end

  -- refresh ts state / parse only current line
  local cursor_row = cursor[1] - 1
  local trees = parser:parse({ cursor_row, cursor_row })
  if trees and not vim.tbl_isempty(trees) then
    -- get node at cursor position with col - 1, so we are inside the written tag
    local opening_node = ts.get_opening_node(
      { bufnr = bufnr, pos = { cursor[1] - 1, cursor[2] - 1 } },
      0
    )
    if opening_node then
      local opening_node_identifier = ts.get_node_identifier(opening_node)
      if opening_node_identifier then
        tag_name = vim.treesitter.get_node_text(opening_node_identifier, bufnr)
      end
    end
  end

  -- Fallback: when tree-sitter cannot recognise the opening tag (e.g. the
  -- cursor sits inside an ERROR node because the surrounding file confuses
  -- the parser, such as Razor/cshtml mixing C# and HTML), recover the tag
  -- name from the textual content of the line. This keeps the auto-close
  -- behaviour working in files with imperfect parses.
  if not tag_name or tag_name == "" then
    tag_name = detect_tag_name_from_line(line, cursor[2])
  end

  if not tag_name or tag_name == "" then
    return
  end

  -- do not close void elements
  if vim.list_contains(void_elements, tag_name) then
    return
  end

  -- check if next char is "/" or ">" "<div|></div>"
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

    if Config.options.disable_in_multicursor then
      if MultiCursor ~= nil and MultiCursor.hasCursors() then
        return
      end
    end

    vim.schedule(function()
      maybe_close_tag(bufnr)
    end)
  end, namespace_id)
end

---@param bufnr integer
---@return nil
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
