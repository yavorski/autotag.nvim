local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    -- This will be executed before every (even nested) case
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ "-u", "scripts/minimal-init.lua" })
      -- Load tested plugin
      child.lua([[AR = require("autotag.rename-tag")]])
      -- Disable auto indent
    end,
    -- This will be executed one after all tests from this set are finished
    post_once = child.stop
  },
  parametrize = {
    { "xml", "xml" },
    { "html", "html" },
    { "razor", "razor" },
    { "htmlangular", "angular" }
  }
})

---@return integer
local function bufnr()
  return child.api.nvim_get_current_buf()
end

---@return integer
local function winnr()
  return child.api.nvim_get_current_win()
end

---@return string[]
local function get_lines()
  local buf = bufnr()
  return child.api.nvim_buf_get_lines(buf, 0, -1, true)
end

---@param lines string|string[]
local function set_lines(lines)
  local buf = bufnr()

  if type(lines) == "string" then
    lines = vim.split(lines, "\n")
  end

  child.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
end

---@return string
local function get_content()
  local buf = bufnr()
  local lines = child.api.nvim_buf_get_lines(buf, 0, -1, true)
  return table.concat(lines, "\n")
end

---@param row integer
---@param col integer
local function set_cursor(row, col)
  local win = winnr()
  child.api.nvim_win_set_cursor(win, { row, col })
end

---@return string char under the cursor
local function get_char_cursor()
  local line = child.api.nvim_get_current_line()
  local char = line:sub(child.fn.col("."), child.fn.col("."))
  return char
end

---@param ft string
---@param ts_lang string
local function init_rename_tag(ft, ts_lang)
  local buf = bufnr()
  child.bo.readonly = false
  child.bo.filetype = ft
  child.bo.indentexpr = ""
  child.treesitter.start(buf, ts_lang)
  child.lua_func(function(buf) AR.init(buf) end, buf)
  child.cmd("doautocmd BufEnter")
end

T["rename-div-a"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<div></div>")

  child.type_keys("a")
  child.type_keys("k-")

  local result = get_content()
  expect.equality(result, "<k-div></k-div>")
end

T["rename-div-i"] = function(ft, ts_lang)
  local result = ""
  init_rename_tag(ft, ts_lang)

  set_lines("<div></div>")

  set_cursor(1, 4)
  expect.equality(get_char_cursor(), ">")

  child.cmd("startinsert")
  child.type_keys("-kk")

  result = get_content()
  expect.equality(result, "<div-kk></div-kk>")

  child.type_keys("<bs><bs><bs>")

  result = get_content()
  expect.equality(result, "<div></div>")

  child.type_keys("<bs><bs><bs>")

  result = get_content()
  expect.equality(result, "<></>")

  child.type_keys("main")

  result = get_content()
  expect.equality(result, "<main></main>")
end

T["rename-div-r"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<div></div>")
  set_cursor(1, 1)
  child.type_keys("rr")

  local result = get_content()
  expect.equality(result, "<riv></riv>")
end

T["rename-div-ciw"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<div></div>")
  set_cursor(1, 1)

  child.type_keys("ciw")
  child.type_keys("main")

  local result = get_content()
  expect.equality(result, "<main></main>")
end

T["rename-self-closing-tag"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines([[<img src="test.jpg" />]])
  set_cursor(1, 1)
  child.type_keys("ciw")
  child.type_keys("video")

  local result = get_content()
  expect.equality(result, [[<video src="test.jpg" />]])
end

T["rename-nested-tags"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<div><span></span></div>")

  set_cursor(1, 6)
  expect.equality(get_char_cursor(), "s")

  child.type_keys("ciw")
  child.type_keys("strong")

  local result = get_content()
  expect.equality(result, "<div><strong></strong></div>")
end

T["rename-tag-with-attributes"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines([[<div class="container" id="main"></div>]])
  set_cursor(1, 1)
  expect.equality(get_char_cursor(), "d")

  child.type_keys("ciw")
  child.type_keys("section")

  local result = get_content()
  expect.equality(result, [[<section class="container" id="main"></section>]])
end

T["rename-multiline-tag"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines([[
    <div>
      <p>content</p>
    </div>
  ]])

  -- start "d"
  set_cursor(1, 5)
  expect.equality(get_char_cursor(), "d")

  child.type_keys("ciw")
  child.type_keys("article")

  local result = get_content()
  expect.equality(result, [[
    <article>
      <p>content</p>
    </article>
  ]])
end

T["rename-from-closing-tag"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<div></div>")

  set_cursor(1, 7)
  expect.equality(get_char_cursor(), "d")

  child.type_keys("ciw")
  child.type_keys("header")

  local result = get_content()
  expect.equality(result, "<header></header>")
end

T["rename-with-backspace-entire-tag"] = function(ft, ts_lang)
  local result = ""
  init_rename_tag(ft, ts_lang)

  set_lines("<button></button>")

  set_cursor(1, 7)
  expect.equality(get_char_cursor(), ">")

  child.cmd("startinsert") -- "i"
  child.type_keys("<bs><bs><bs><bs><bs><bs>")

  result = get_content()
  expect.equality(result, "<></>")

  child.type_keys("a")

  result = get_content()
  expect.equality(result, "<a></a>")
end

T["rename-complex-nested-structure"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines([[
    <div>
      <ul>
        <li>item</li>
      </ul>
    </div>
  ]])

  -- start "u"
  set_cursor(2, 7)
  expect.equality(get_char_cursor(), "u")

  child.type_keys("ciw")
  child.type_keys("ol")

  local result = get_content()

  expect.equality(result, [[
    <div>
      <ol>
        <li>item</li>
      </ol>
    </div>
  ]])
end

T["rename-tag-insert-mode-middle"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<div></div>")
  set_cursor(1, 2)

  child.cmd("startinsert")
  child.type_keys("av")

  local result = get_content()
  expect.equality(result, "<daviv></daviv>")
end

T["rename-tag-to-custom-element"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<div></div>")
  set_cursor(1, 1)
  child.type_keys("ciw")
  child.type_keys("my-custom-element")

  local result = get_content()
  expect.equality(result, "<my-custom-element></my-custom-element>")
end

T["rename-deeply-nested-tags"] = function(ft, ts_lang)
  local result = ""
  init_rename_tag(ft, ts_lang)

  set_lines([[
    <div>
      <section>
        <article>
          <header>title</header>
        </article>
      </section>
    </div>
  ]])

  -- start "h"
  set_cursor(4, 11)

  child.type_keys("ciw")
  child.type_keys("h1")

  result = get_content()
  expect.equality(result, [[
    <div>
      <section>
        <article>
          <h1>title</h1>
        </article>
      </section>
    </div>
  ]])

  child.cmd("stopinsert")

  -- start "d"
  set_cursor(1, 5)

  child.type_keys("ciw")
  child.type_keys("main")

  result = get_content()
  expect.equality(result, [[
    <main>
      <section>
        <article>
          <h1>title</h1>
        </article>
      </section>
    </main>
  ]])
end

T["rename-tag-replace-mode"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<kbd></kbd>")
  set_cursor(1, 1)

  child.type_keys("R")
  child.type_keys("div")

  local result = get_content()
  expect.equality(result, "<div></div>")
end

T["rename-tag-with-content"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<p>Hello World</p>")
  set_cursor(1, 1)

  child.type_keys("ciw")
  child.type_keys("h1")

  local result = get_content()
  expect.equality(result, "<h1>Hello World</h1>")
end

-- FIXME ?
-- this won't work, tree-sitter is returning error for "<></>", so there is no actual TS node
T["rename-empty-tags"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<></>")
  set_cursor(1, 0)

  -- append after "<"
  child.type_keys("a")
  child.type_keys("div")

  local result = get_content()
  expect.equality(result, "<div></>")
end

T["rename-tag-visual-mode"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines("<button></button>")
  set_cursor(1, 1)

  child.type_keys("viw")
  child.type_keys("c")
  child.type_keys("section")

  local result = get_content()
  expect.equality(result, "<section></section>")
end

T["replace-single-char"] = function (ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines([[
    <div>
      <p>Lorem</p>
    </div>
  ]])

  set_cursor(2, 7)
  expect.equality(get_char_cursor(), "p")

  -- replace "p" with "a"
  child.type_keys("ra")

  local result = get_content()
  expect.equality(result, [[
    <div>
      <a>Lorem</a>
    </div>
  ]])
end

T["replace-single-char-middle"] = function (ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines([[<div></div>]])

  set_cursor(1, 2)
  expect.equality(get_char_cursor(), "i")

  -- replace "i" with "x"
  child.type_keys("rx")

  local result = get_content()
  expect.equality(result, [[<dxv></dxv>]])
end

T["replace-multiple-chars"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  set_lines([[<div></div>]])

  set_cursor(1, 1)
  expect.equality(get_char_cursor(), "d")

  -- replace char and move to the next char
  child.type_keys("rr", "l")
  expect.equality(get_content(), [[<riv></riv>]])

  child.type_keys("rr", "l")
  expect.equality(get_content(), [[<rrv></rrv>]])

  child.type_keys("rr", "l")
  expect.equality(get_content(), [[<rrr></rrr>]])
end

-- undo after delete should result in wrongly closed tags
-- deleting the div tag with dd and then undo should not result in corrupted p tag -> `<p>Lorem</div>`
-- <div>
--   <p>Lorem</p>
-- </div>
T["undo-after-delete"] = function(ft, ts_lang)
  local result = ""
  init_rename_tag(ft, ts_lang)

  set_lines([[
    <div>
      <p>Lorem</p>
    </div>
  ]])

  set_cursor(1, 7)
  expect.equality(get_char_cursor(), "v")

  child.type_keys("dd")

  result = get_content()
  expect.equality(result, [[
      <p>Lorem</p>
    </div>
  ]])

  -- undo
  child.type_keys("u")

  result = get_content()
  expect.equality(result, [[
    <div>
      <p>Lorem</p>
    </div>
  ]])
end

-- deleting tag with dd should not delete the closing tag or update it to "</>"
-- this very useful when you want to move up and down the opening tag
T["delete-line-dd"] = function(ft, ts_lang)
  local result = ""
  init_rename_tag(ft, ts_lang)

  set_lines([[
    <section>
      <div>
        <p>Lorem ipsum dolor sit amet.</p>
      </div>
    </section>
  ]])

  set_cursor(1, 0)

  child.type_keys("dd")

  result = get_content()
  expect.equality(result, [[
      <div>
        <p>Lorem ipsum dolor sit amet.</p>
      </div>
    </section>
  ]])

  child.type_keys("dd")

  result = get_content()
  expect.equality(result, [[
        <p>Lorem ipsum dolor sit amet.</p>
      </div>
    </section>
  ]])
end

-- deleting whole line should not throw error from invalid indexes
-- <div></div>
T["delete-line-dd-multiple-positions"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  for i = 0, 10 do
    set_lines([[<div></div>]])
    set_cursor(1, i)
    child.type_keys("dd")
    expect.equality(get_content(), "")
  end
end

-- deleting the first div tag/line with dd should not result in -> `div </div>`
-- <div>
-- </div>
T["delete-line-dd-multiple-positions-multiline"] = function(ft, ts_lang)
  init_rename_tag(ft, ts_lang)

  for i = 0, 10 do
    set_lines([[
      <div>
      </div>
    ]])

    set_cursor(1, i)
    child.type_keys("dd")
    expect.equality(get_content(), [[
      </div>
    ]])
  end
end

-- Similar to "dd" -> [ "cc", "C", "S" ]
T["delete-line-cc"] = function(ft, ts_lang)
  local result = ""
  init_rename_tag(ft, ts_lang)

  set_lines([[
    <section>
      <div>
        <p>Lorem ipsum dolor sit amet.</p>
      </div>
    </section>
  ]])

  set_cursor(1, 0)

  -- "C" - Delete from the cursor position to the end of the line and [count]-1 more lines [into register x], and start insert. Synonym for c$
  child.type_keys("C")
  child.cmd("stopinsert")
  child.type_keys("dd") -- delete empty line

  result = get_content()
  expect.equality(result, [[
      <div>
        <p>Lorem ipsum dolor sit amet.</p>
      </div>
    </section>
  ]])

  -- "S" - Delete [count] lines [into register x] and start insert. Synonym for "cc"
  child.type_keys("S")
  child.cmd("stopinsert")
  child.type_keys("dd") -- delete empty line from first "C" deletion

  result = get_content()
  expect.equality(result, [[
        <p>Lorem ipsum dolor sit amet.</p>
      </div>
    </section>
  ]])
end

return T
