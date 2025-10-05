local ts = require("autotag.ts")
local Config = require("autotag.config")

local M = {}

local NS_EXTMARKS = vim.api.nvim_create_namespace("autotag/rename-tag-extmarks")

---@param bufnr integer
local function clear_extmarks(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_EXTMARKS, 0, -1)
end

---@param opts vim.api.keyset.set_extmark
local function make_extmark_options(opts)
  return vim.tbl_extend("force", {
    invalidate = false,
    right_gravity = false,
    end_right_gravity = true,
  }, opts)
end

---@param bufnr integer
local function update_sibling_extmarks(bufnr)
  local aliased_lang = ts.get_aliased_lang(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, aliased_lang)
  if not ok or not parser then
    return
  end

  -- FIXME ?
  if aliased_lang then
    parser:parse()
  end

  local opening_node, closing_node = ts.get_opening_pair(bufnr)
  if not opening_node or not closing_node then
    closing_node, opening_node = ts.get_closing_pair(bufnr)
  end
  if not opening_node or not closing_node then
    return
  end

  if ts.has_error(opening_node) or ts.has_error(closing_node) then
    return
  end

  local opening_node_identifier = ts.get_node_identifier(opening_node)
  ---@type Autotag.NodeIndices
  local opening_indices
  if opening_node_identifier then
    opening_indices = ts.get_node_indices(opening_node_identifier)
  else
    opening_indices = ts.get_node_indices(opening_node)
    opening_indices.start_col = opening_indices.start_col + 1
    opening_indices.end_col = opening_indices.end_col - 1
  end

  local closing_node_identifier = ts.get_node_identifier(closing_node)
  ---@type Autotag.NodeIndices
  local closing_indices
  if closing_node_identifier then
    closing_indices = ts.get_node_indices(closing_node_identifier)
  else
    closing_indices = ts.get_node_indices(closing_node)
    closing_indices.start_col = closing_indices.start_col + 2
    closing_indices.end_col = closing_indices.end_col - 1
  end

  clear_extmarks(bufnr)
  local id = vim.api.nvim_buf_set_extmark(
    bufnr,
    NS_EXTMARKS,
    opening_indices.start_row,
    opening_indices.start_col,
    make_extmark_options({
      end_col = opening_indices.end_col,
      end_row = opening_indices.end_row,
    })
  )
  vim.api.nvim_buf_set_extmark(
    bufnr,
    NS_EXTMARKS,
    closing_indices.start_row,
    closing_indices.start_col,
    make_extmark_options({
      id = id + 1,
      end_col = closing_indices.end_col,
      end_row = closing_indices.end_row,
    })
  )
end

---@param bufnr integer
local function get_cursor_identifier_extmark(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local iden_ext = vim.api.nvim_buf_get_extmarks(
    bufnr,
    NS_EXTMARKS,
    { cursor[1] - 1, cursor[2] },
    { cursor[1] - 1, cursor[2] },
    { overlap = true, details = true, limit = 1 }
  )
  if not iden_ext[1] then
    return
  end

  if type(iden_ext[1][1]) == "table" then
    clear_extmarks(bufnr)
    return
  end

  return iden_ext[1]
end

---@param bufnr integer
---@param pair_id_offset integer
local function sync_pair(bufnr, pair_id_offset)
  local ext1 = get_cursor_identifier_extmark(bufnr)
  if not ext1 then
    return
  end
  local ext2 = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_EXTMARKS, ext1[1] + pair_id_offset, {
    details = true,
  })
  if not ext2[1] then
    return
  end

  local text1 = vim.api.nvim_buf_get_text(bufnr, ext1[2], ext1[3], ext1[4].end_row, ext1[4].end_col, {})[1]
  if not text1 then
    clear_extmarks(bufnr)
    return
  end

  if text1:find("/") or text1:find("<") or text1:find(">") then
    clear_extmarks(bufnr)
    return
  end

  local before, after = text1:match("(.-) (.*)")
  if before and after then
    text1 = before
    vim.api.nvim_buf_set_extmark(
      bufnr,
      NS_EXTMARKS,
      ext1[2],
      ext1[3],
      make_extmark_options({
        id = ext1[1],
        end_col = assert(ext1[4]).end_col - #after - 1,
        end_row = assert(ext1[4]).end_row,
      })
    )
  end

  local text2 = vim.api.nvim_buf_get_text(bufnr, ext2[1], ext2[2], ext2[3].end_row, ext2[3].end_col, {})[1]
  if text1 == text2 then
    return
  end

  vim.api.nvim_buf_set_text(bufnr, ext2[1], ext2[2], ext2[3].end_row, ext2[3].end_col, { text1 })
end

---@param bufnr integer
function M.init(bufnr)
  local augroup = vim.api.nvim_create_augroup(string.format("autotag/rename-tag-auto-init-%d", bufnr), {})

  -- Sync/Rename tag pairs during editing
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = function(ev)
      if Config.options.disable_in_macro and vim.fn.reg_recording() ~= "" then
        return
      end
      sync_pair(ev.buf, 1)
      sync_pair(ev.buf, -1)
    end
  })

  -- Update extmarks on cursor movement
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = vim.schedule_wrap(function(ev)
      if vim.api.nvim_get_current_buf() ~= ev.buf then
        return
      end

      if Config.options.disable_in_macro and vim.fn.reg_recording() ~= "" then
        return
      end

      if not get_cursor_identifier_extmark(ev.buf) then
        clear_extmarks(ev.buf)
        update_sibling_extmarks(ev.buf)
      end
    end)
  })
end

return M
