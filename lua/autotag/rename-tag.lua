local ts = require("autotag.ts")
local Config = require("autotag.config")

local M = {}

local NS_EXTMARKS = vim.api.nvim_create_namespace("autotag/rename-tag-extmarks")

---@param bufnr integer
local function clear_extmarks(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_EXTMARKS, 0, -1)
end

---@param text1 string
---@param text2 string
---@return boolean true if extmarks should be cleared (stale), false otherwise
local function are_extmarks_stale(text1, text2)
  -- Detect stale extmarks: if we're syncing between completely different tag types
  -- (like "div" and "p"), this suggests extmarks became stale after dd/u operations
  if text1 == text2 or text1 == "" or text2 == "" then
    return false
  end

  local mode = vim.fn.mode()

  -- In replace mode or insert mode, allow complete tag name changes (that's normal)
  -- Only validate for stale extmarks in normal mode
  if mode ~= "n" then
    return false
  end

  -- Check if the tag names look completely unrelated (not a partial edit)
  local text1_clean = text1:gsub("^%s*", ""):gsub("%s.*$", "")
  local text2_clean = text2:gsub("^%s*", ""):gsub("%s.*$", "")

  -- Only clear if they're completely different words with no shared characters
  -- This catches cases like "div" vs "p" but allows "div" vs "riv" or "daviv"
  if text1_clean == text2_clean or
     not text1_clean:match("^[a-zA-Z][a-zA-Z0-9%-]*$") or
     not text2_clean:match("^[a-zA-Z][a-zA-Z0-9%-]*$") then
    return false
  end

  -- Special case: allow single-character to single-character transitions
  -- (like "p" → "a"), but still block multi-char to single-char if unrelated
  if #text1_clean == 1 and #text2_clean == 1 then
    -- Allow any single-character to single-character tag change (p→a, i→b, etc.)
    return false
  elseif (#text1_clean == 1 and #text2_clean > 1) or (#text2_clean == 1 and #text1_clean > 1) then
    -- Mixed single/multi character - check if they're plausibly related
    -- Allow if the single char appears in the multi-char word
    local single_char = #text1_clean == 1 and text1_clean or text2_clean
    local multi_char = #text1_clean > 1 and text1_clean or text2_clean
    if not multi_char:find(single_char) then
      return true
    end
    return false
  else
    -- Check if they share any significant substring (indicating partial edit)
    -- For strings of similar length, also check single character overlaps
    local has_shared_content = false

    -- First check for 2+ character substrings (stronger evidence of relation)
    for i = 1, #text1_clean - 1 do
      if text2_clean:find(text1_clean:sub(i, i + 1)) then
        has_shared_content = true
        break
      end
    end

    -- If not found yet, check substrings of text2_clean in text1_clean
    if not has_shared_content then
      for i = 1, #text2_clean - 1 do
        if text1_clean:find(text2_clean:sub(i, i + 1)) then
          has_shared_content = true
          break
        end
      end
    end

    -- If no 2+ char substrings but strings are similar length (suggesting single-char edit),
    -- check if they share significant single characters (at least 2 common chars)
    if not has_shared_content and math.abs(#text1_clean - #text2_clean) <= 1 then
      local common_chars = 0
      for i = 1, #text1_clean do
        if text2_clean:find(text1_clean:sub(i, i)) then
          common_chars = common_chars + 1
        end
      end
      if common_chars >= 2 then
        has_shared_content = true
      end
    end

    return not has_shared_content
  end
end

---@param opts vim.api.keyset.set_extmark
local function make_extmark_options(opts)
  return vim.tbl_extend("force", {
    invalidate = false,
    right_gravity = false,
    end_right_gravity = true,
  }, opts)
end

---@param delimiter? string
---@return boolean
local function is_cursor_on_delimiter(delimiter)
  local char = vim.api.nvim_get_current_line():sub(vim.fn.col("."), vim.fn.col("."))

  if delimiter ~= nil then
    return char == delimiter
  end

  return char == "<" or char == "/" or char == ">"
end

---@param indices AutoTag.NodeIndices
---@return boolean
local function is_cursor_on_identifier(indices)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row, cursor_col = cursor[1] - 1, cursor[2]
  local mode = vim.fn.mode()

  local end_col = indices.end_col
  if mode == "i" or mode == "R" then
    end_col = end_col + 1
  end

  return cursor_row >= indices.start_row and cursor_row <= indices.end_row and cursor_col >= indices.start_col and cursor_col < end_col
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
    -- FIXME
    if not aliased_lang then
      return
    end
  end

  local opening_node_identifier = ts.get_node_identifier(opening_node)
  ---@type AutoTag.NodeIndices
  local opening_indices
  if opening_node_identifier then
    opening_indices = ts.get_node_indices(opening_node_identifier)
  else
    opening_indices = ts.get_node_indices(opening_node)
    opening_indices.start_col = opening_indices.start_col + 1
    opening_indices.end_col = opening_indices.end_col - 1
  end

  local closing_node_identifier = ts.get_node_identifier(closing_node)
  ---@type AutoTag.NodeIndices
  local closing_indices
  if closing_node_identifier then
    closing_indices = ts.get_node_indices(closing_node_identifier)
  else
    closing_indices = ts.get_node_indices(closing_node)
    closing_indices.start_col = closing_indices.start_col + 2
    closing_indices.end_col = closing_indices.end_col - 1
  end

  -- Prevents deletion of the end tag when using "dd"
  -- Only create extmarks if cursor is on tag identifier, not on delimiters like '<' or '>'
  if aliased_lang then
    if is_cursor_on_delimiter("<") then
      return
    end
  else
    if not is_cursor_on_identifier(opening_indices) and not is_cursor_on_identifier(closing_indices) then
      return
    end
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

  local ext = iden_ext[1]

  -- Check if the extmark positions are still valid in the buffer
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if ext[2] >= line_count or ext[4].end_row >= line_count then
    clear_extmarks(bufnr)
    return
  end

  -- Get the actual line content to validate column bounds
  local start_line = vim.api.nvim_buf_get_lines(bufnr, ext[2], ext[2] + 1, false)[1]
  local end_line = vim.api.nvim_buf_get_lines(bufnr, ext[4].end_row, ext[4].end_row + 1, false)[1]

  if not start_line or not end_line or
     ext[3] >= #start_line or ext[4].end_col > #end_line then
    clear_extmarks(bufnr)
    return
  end

  -- Validate that the extmark points to content that makes sense at the current cursor
  local ext_text = vim.api.nvim_buf_get_text(bufnr, ext[2], ext[3], ext[4].end_row, ext[4].end_col, {})[1]
  if not ext_text or ext_text:find("/") or ext_text:find("<") or ext_text:find(">") then
    clear_extmarks(bufnr)
    return
  end

  return ext
end

---Validates if a buffer position is within valid bounds
---@param bufnr integer The buffer number to check
---@param row integer The row position (0-indexed)
---@param col integer The column position (0-indexed)
---@param is_end_pos boolean Whether this is an end position (allows col = line_length + 1)
---@return boolean is_valid True if the position is within buffer bounds
local function is_position_valid(bufnr, row, col, is_end_pos)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if row >= line_count or row < 0 then
    return false
  end

  local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line_text then
    return false
  end

  -- For end positions, allow col to be line_length + 1 (past end of line)
  local max_col = is_end_pos and (#line_text + 1) or #line_text
  return col >= 0 and col <= max_col
end

---@param bufnr integer
---@param pair_id_offset integer
local function sync_pair(bufnr, pair_id_offset)
  local ext1 = get_cursor_identifier_extmark(bufnr)
  if not ext1 then
    return
  end

  local ext2 = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_EXTMARKS, ext1[1] + pair_id_offset, { details = true })
  if not ext2[1] then
    return
  end

  -- Comprehensive bounds validation
  if not is_position_valid(bufnr, ext1[2], ext1[3], false) or
    not is_position_valid(bufnr, ext1[4].end_row, ext1[4].end_col, true) or
    not is_position_valid(bufnr, ext2[1], ext2[2], false) or
    not is_position_valid(bufnr, ext2[3].end_row, ext2[3].end_col, true) then
    clear_extmarks(bufnr)
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

  local text2 = vim.api.nvim_buf_get_text(bufnr, ext2[1], ext2[2], ext2[3].end_row, ext2[3].end_col, {})[1]
  if not text2 then
    clear_extmarks(bufnr)
    return
  end

  if text2:find("/") or text2:find("<") or text2:find(">") then
    clear_extmarks(bufnr)
    return
  end

  if are_extmarks_stale(text1, text2) then
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

  if text1 == text2 then
    return
  end

  -- Abort sync if ext2 points to column 0 - stale extmarks after line deletion with "dd"
  if ext2[2] == 0 then
    clear_extmarks(bufnr)
    return
  end

  vim.api.nvim_buf_set_text(bufnr, ext2[1], ext2[2], ext2[3].end_row, ext2[3].end_col, { text1 })
end

---@param bufnr integer
---@return boolean
local function should_init(bufnr)
  if vim.api.nvim_get_current_buf() ~= bufnr then
    return false
  end

  if Config.options.disable_in_macro and vim.fn.reg_recording() ~= "" then
    return false
  end

  return true
end

---@param bufnr integer
---@return nil
function M.init(bufnr)
  local augroup = vim.api.nvim_create_augroup(string.format("autotag/rename-tag-%d", bufnr), {})

  -- Sync/Rename tag pairs during editing
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = function(ev)
      if not should_init(ev.buf) then
        return
      end

      if not get_cursor_identifier_extmark(ev.buf) then
        update_sibling_extmarks(ev.buf)
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
      if not should_init(ev.buf) then
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
