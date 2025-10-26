local ts = require("autotag.ts")
local Config = require("autotag.config")

local M = {}

local NS_EXTMARKS = vim.api.nvim_create_namespace("autotag/rename-tag-extmarks")

---@param bufnr integer
local function clear_extmarks(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_EXTMARKS, 0, -1)
end

---@param text string
---@return string cleaned tag name (removes whitespace and attributes)
local function clean_tag_name(text)
  return text:gsub("^%s*", ""):gsub("%s.*$", "")
end

---@param text string
---@return boolean true if text looks like a valid HTML tag name
local function is_valid_tag_name(text)
  return text:match("^[a-zA-Z][a-zA-Z0-9%-]*$") ~= nil
end

---@param text1_clean string
---@param text2_clean string
---@return boolean true if strings share enough content to suggest partial edit
local function share_common_content(text1_clean, text2_clean)
  -- Check for 2+ character substrings (strong evidence of relation)
  for i = 1, #text1_clean - 1 do
    if text2_clean:find(text1_clean:sub(i, i + 1)) then
      return true
    end
  end

  for i = 1, #text2_clean - 1 do
    if text1_clean:find(text2_clean:sub(i, i + 1)) then
      return true
    end
  end

  -- For similar length strings, check if they share at least 2 characters
  if math.abs(#text1_clean - #text2_clean) <= 1 then
    local common_chars = 0
    for i = 1, #text1_clean do
      if text2_clean:find(text1_clean:sub(i, i)) then
        common_chars = common_chars + 1
      end
    end
    return common_chars >= 2
  end

  return false
end

---@param text1 string
---@param text2 string
---@return boolean true if extmarks should be cleared (stale), false otherwise
local function are_extmarks_stale(text1, text2)
  -- Don't clear if same, empty, or not in normal mode
  if text1 == text2 or text1 == "" or text2 == "" or vim.fn.mode() ~= "n" then
    return false
  end

  local text1_clean = clean_tag_name(text1)
  local text2_clean = clean_tag_name(text2)

  -- Don't clear if same after cleaning or invalid tag names
  if text1_clean == text2_clean or not is_valid_tag_name(text1_clean) or not is_valid_tag_name(text2_clean) then
    return false
  end

  -- Allow single-char to single-char transitions (p→a, i→b, etc.)
  if #text1_clean == 1 and #text2_clean == 1 then
    return false
  end

  -- For single/multi-char mixed: allow if single char appears in multi-char
  if (#text1_clean == 1 and #text2_clean > 1) or (#text2_clean == 1 and #text1_clean > 1) then
    local single_char = #text1_clean == 1 and text1_clean or text2_clean
    local multi_char = #text1_clean > 1 and text1_clean or text2_clean
    return not multi_char:find(single_char)
  end

  -- For multi-char: clear only if they don't share common content
  return not share_common_content(text1_clean, text2_clean)
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
    if not aliased_lang then
      return
    end
  end

  -- Get indices for opening tag (skip < and >)
  local opening_node_identifier = ts.get_node_identifier(opening_node)
  local opening_indices = opening_node_identifier and ts.get_node_indices(opening_node_identifier) or ts.get_node_indices(opening_node)
  if not opening_node_identifier then
    opening_indices.start_col = opening_indices.start_col + 1
    opening_indices.end_col = opening_indices.end_col - 1
  end

  -- Get indices for closing tag (skip </ and >)
  local closing_node_identifier = ts.get_node_identifier(closing_node)
  local closing_indices = closing_node_identifier and ts.get_node_indices(closing_node_identifier) or ts.get_node_indices(closing_node)
  if not closing_node_identifier then
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

---Checks if buffer position is safe to access (prevents crashes on deleted/invalid positions)
---@param bufnr integer Buffer number to validate against
---@param row integer Row position (0-indexed)
---@param col integer Column position (0-indexed)
---@param is_end_pos? boolean If true, allows col = line_length + 1 (for range end positions)
---@return boolean True if position exists and can be safely accessed
local function is_position_valid(bufnr, row, col, is_end_pos)
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  if row < 0 or row >= line_count then
    return false
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]

  if not line then
    return false
  end

  local max_col = is_end_pos and (#line + 1) or #line

  return col >= 0 and col <= max_col
end

---@param text string
---@return boolean
local function is_valid_tag_text(text)
  return text and not text:find("[</>]")
end

---@param bufnr integer
local function get_cursor_identifier_extmark(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local extmarks = vim.api.nvim_buf_get_extmarks(
    bufnr, NS_EXTMARKS,
    { cursor[1] - 1, cursor[2] },
    { cursor[1] - 1, cursor[2] },
    { overlap = true, details = true, limit = 1 }
  )

  if not extmarks[1] or type(extmarks[1][1]) == "table" then
    clear_extmarks(bufnr)
    return
  end

  local ext = extmarks[1]

  -- Validate positions and content
  if not is_position_valid(bufnr, ext[2], ext[3]) or
     not is_position_valid(bufnr, ext[4].end_row, ext[4].end_col, true) then
    clear_extmarks(bufnr)
    return
  end

  local ok, text = pcall(vim.api.nvim_buf_get_text, bufnr, ext[2], ext[3], ext[4].end_row, ext[4].end_col, {})
  if not ok or not text[1] or not is_valid_tag_text(text[1]) then
    clear_extmarks(bufnr)
    return
  end

  return ext
end

---@param bufnr integer
---@param pair_id_offset integer
local function sync_pair(bufnr, pair_id_offset)
  local ext1 = get_cursor_identifier_extmark(bufnr)
  if not ext1 then return end

  local ext2 = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_EXTMARKS, ext1[1] + pair_id_offset, { details = true })
  if not ext2[1] then return end

  -- Validate second extmark position
  if not is_position_valid(bufnr, ext2[1], ext2[2]) or
     not is_position_valid(bufnr, ext2[3].end_row, ext2[3].end_col, true) then
    clear_extmarks(bufnr)
    return
  end

  -- Get text content safely
  local ok1, text1_tbl = pcall(vim.api.nvim_buf_get_text, bufnr, ext1[2], ext1[3], ext1[4].end_row, ext1[4].end_col, {})
  local ok2, text2_tbl = pcall(vim.api.nvim_buf_get_text, bufnr, ext2[1], ext2[2], ext2[3].end_row, ext2[3].end_col, {})

  if not ok1 or not ok2 or not text1_tbl[1] or not text2_tbl[1] then
    clear_extmarks(bufnr)
    return
  end

  local text1, text2 = text1_tbl[1], text2_tbl[1]

  -- Check if extmarks point to actual tag positions by examining surrounding context
  local function is_extmark_in_valid_tag_context(row, start_col, end_col)
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if not line then return false end

    -- Check if we have '<' before and '>' after (or start of line)
    local has_open_bracket = start_col > 0 and (line:sub(start_col, start_col) == '<' or line:sub(start_col - 1, start_col - 1) == '<')
    local has_close_bracket = end_col <= #line and (line:sub(end_col + 1, end_col + 1) == '>' or line:find('>', end_col))

    return has_open_bracket and has_close_bracket
  end

  -- If either extmark is not in a valid tag context, clear extmarks
  if not is_extmark_in_valid_tag_context(ext1[2], ext1[3], ext1[4].end_col) or
     not is_extmark_in_valid_tag_context(ext2[1], ext2[2], ext2[3].end_col) then
    clear_extmarks(bufnr)
    return
  end

  -- Validate text content and check for staleness
  if not is_valid_tag_text(text1) or not is_valid_tag_text(text2) or
     are_extmarks_stale(text1, text2) or ext2[2] == 0 then
    clear_extmarks(bufnr)
    return
  end

  -- Handle tag with attributes (extract just the tag name)
  local before, after = text1:match("(.-) (.*)")
  if before and after then
    text1 = before
    vim.api.nvim_buf_set_extmark(bufnr, NS_EXTMARKS, ext1[2], ext1[3], make_extmark_options({
      id = ext1[1],
      end_col = ext1[4].end_col - #after - 1,
      end_row = ext1[4].end_row,
    }))
  end

  -- Sync the tag names if different
  if text1 ~= text2 then
    vim.api.nvim_buf_set_text(bufnr, ext2[1], ext2[2], ext2[3].end_row, ext2[3].end_col, { text1 })
  end
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
