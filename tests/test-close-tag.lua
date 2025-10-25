local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    -- This will be executed before every (even nested) case
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ "-u", "scripts/minimal-init.lua" })
      -- Load tested plugin
      child.lua([[AC = require("autotag.close-tag")]])
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

---@param ft string
---@param ts_lang string
local function init_close_tag(ft, ts_lang)
  local buf = bufnr()
  child.bo.readonly = false
  child.bo.filetype = ft
  child.bo.indentexpr = ""
  child.treesitter.start(buf, ts_lang)
  child.lua_func(function(buf) AC.init(buf) end, buf)
  child.cmd("doautocmd BufEnter")
end

T["close-div"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  child.cmd("startinsert!")
  child.type_keys("<", "div", ">")

  local lines = get_lines()
  expect.equality(lines, { "<div></div>" })
end

T["close-inner-div"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  set_lines({
    "<div>",
      "",
    "</div>"
  })

  child.cmd("normal! 2G")
  child.cmd("startinsert!")
  child.type_keys("<", "div", ">")

  local lines = get_lines()
  expect.equality(lines, {
    "<div>",
      "<div></div>",
    "</div>"
  })
end

T["close-inner-p"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  set_lines({
    "<div>",
      "",
    "</div>"
  })

  child.cmd("normal! 2G")
  child.cmd("startinsert!")
  child.type_keys("<", "p", ">")

  local lines = get_lines()
  expect.equality(lines, {
    "<div>",
      "<p></p>",
    "</div>"
  })
end

T["close-inner-tags"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  set_lines({
    "<div>",
      "<div>",
        "",
      "</div>",
    "</div>"
  })

  child.cmd("normal! 3G")
  child.cmd("startinsert!")
  child.type_keys("<", "div", ">")

  local lines = get_lines()
  expect.equality(lines, {
    "<div>",
      "<div>",
        "<div></div>",
      "</div>",
    "</div>"
  })
end

T["razor-close-tags"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  set_lines({
    "@if (true) {",
      "",
    "} else {",
      "",
    "}"
  })

  child.cmd("normal! 2G")
  child.cmd("startinsert!")

  child.type_keys("<", "div", ">")
  child.type_keys("<", "p", ">")
  child.type_keys("<", "a", ">")
  child.type_keys("Link 1")

  child.cmd("stopinsert")
  child.cmd("normal! 4G")
  child.cmd("startinsert!")

  child.type_keys("<", "div", ">")
  child.type_keys("<", "p", ">")
  child.type_keys("<", "a", ">")
  child.type_keys("Link 2")

  local lines = get_lines()
  expect.equality(lines, {
    "@if (true) {",
      "<div><p><a>Link 1</a></p></div>",
    "} else {",
      "<div><p><a>Link 2</a></p></div>",
    "}"
  })
end

T["razor-close-tags-complex"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  local content = [[
    <main>
      @using System;
      @using Web.Core.Identity;

      @Html.Action("Index", "UserName", new {
        userName = this.userName,
      });

      <div>
        @if (this.userName == this.root.userName) {
          <div>

          </div>
        }
        else {
          <div>

          </div>
        }
      </div>
    </main>
  ]]

  set_lines(content)

  child.cmd("normal! 12G")
  child.cmd("startinsert!")

  child.type_keys("            ")
  child.type_keys("<", "div", ">")
  child.type_keys("<", "p", ">")
  child.type_keys("<", "a", ">")
  child.type_keys("Link 1")
  child.cmd("stopinsert")

  child.cmd("normal! 17G")
  child.cmd("startinsert!")

  child.type_keys("            ")
  child.type_keys("<", "div", ">")
  child.type_keys("<", "p", ">")
  child.type_keys("<", "a", ">")
  child.type_keys("Link 2")
  child.cmd('stopinsert')

  local result = get_content()
  local expected = [[
    <main>
      @using System;
      @using Web.Core.Identity;

      @Html.Action("Index", "UserName", new {
        userName = this.userName,
      });

      <div>
        @if (this.userName == this.root.userName) {
          <div>
            <div><p><a>Link 1</a></p></div>
          </div>
        }
        else {
          <div>
            <div><p><a>Link 2</a></p></div>
          </div>
        }
      </div>
    </main>
  ]]

  expect.equality(result, expected)
end

T["close-custom-tags"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  child.cmd("startinsert!")
  child.type_keys("<", "My-Main", ">")
  child.type_keys("<", "My-Section", ">")
  child.type_keys("<", "My-Div", ">")
  child.type_keys("<", "p", ">")
  child.type_keys("Lorem Ipsum")

  local lines = get_lines()
  expect.equality(lines, { "<My-Main><My-Section><My-Div><p>Lorem Ipsum</p></My-Div></My-Section></My-Main>" })
end

T["void-elements"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  local void_elements = { "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr" }

  child.cmd("startinsert!")

  for _, tag in pairs(void_elements) do
    child.type_keys("<", tag, ">")
  end

  local lines = get_lines()
  local expected = vim.tbl_map(function(tag) return string.format("<%s>", tag) end, void_elements)

  expect.equality(lines[1], table.concat(expected, ""))
end

T["void-elements-self"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  local void_elements = { "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr" }

  child.cmd("startinsert!")

  for _, tag in pairs(void_elements) do
    child.type_keys("<", tag, " />")
  end

  local lines = get_lines()
  local expected = vim.tbl_map(function(tag) return string.format("<%s />", tag) end, void_elements)

  expect.equality(lines[1], table.concat(expected, ""))
end

T["disabled-in-macro"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  -- start macro rec
  child.cmd("normal! qM")
  child.cmd("startinsert!")
  child.type_keys("<", "div", ">")

  local lines = get_lines()

  -- should not be closed
  expect.equality(lines, { "<div>" })
end

T["enabled-in-macro"] = function(ft, ts_lang)
  child.lua([[require("autotag.config").options.disable_in_macro = false]])
  init_close_tag(ft, ts_lang)

  -- start macro rec
  child.cmd("normal! qM")
  child.cmd("startinsert!")
  child.type_keys("<", "div", ">")

  local lines = get_lines()

  -- should be closed
  expect.equality(lines, { "<div></div>" })
end

T["close-tags-with-attrs"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  child.cmd("startinsert!")

  -- self closing
  child.type_keys("<", [[wbr class="wbr"]], "/>", "<cr>")
  child.type_keys("<", [[input type="text" class="input"]], "/>", "<cr>")
  child.type_keys("<", [[a href="https://www.ahref.io/" target="_blank" class="link"]], "/>", "<cr>")
  child.type_keys("<", [[img src="https://www.img.io/img.png" alt="text" class="image"]], "/>", "<cr>")

  -- no self closing
  child.type_keys("<", [[div class="div"]], ">")
  child.cmd("normal! o")
  child.type_keys("<", [[main class="main"]], ">")
  child.cmd("normal! o")
  child.type_keys("<", [[header class="header"]], ">")
  child.cmd("normal! o")
  child.type_keys("<", [[footer class="footer"]], ">")

  local lines = get_lines()

  local expected = {
    [[<wbr class="wbr"/>]],
    [[<input type="text" class="input"/>]],
    [[<a href="https://www.ahref.io/" target="_blank" class="link"/>]],
    [[<img src="https://www.img.io/img.png" alt="text" class="image"/>]],
    [[<div class="div"></div>]],
    [[<main class="main"></main>]],
    [[<header class="header"></header>]],
    [[<footer class="footer"></footer>]],
  }

  expect.equality(lines, expected)
end

-- special
T["close-tags-with-underscores"] = function(ft, ts_lang)
  local result = nil
  init_close_tag(ft, ts_lang)

  child.cmd("startinsert!")

  -- dashes works fine
  child.type_keys("<", "my-xyz", ">")
  result = get_lines()
  expect.equality(result, { "<my-xyz></my-xyz>" })

  -- delete buf content
  child.cmd("%delete")

  -- tree-sitter HTML parser identies "_xyz" as attribute node
  child.type_keys("<", "my_xyz", ">")
  result = get_lines()

  if ft == "xml" then
    -- works for XML
    expect.equality(result, { "<my_xyz></my_xyz>" })
  else
    -- NOTE does not work for HTML, Razor, Angular!
    -- FIXME handle/fix this behavior in the plugin?
    expect.equality(result, { "<my_xyz></my>" })
  end

  -- delete buf content
  child.cmd("%delete")

  -- NOTE Custom element containg "dash" and "underscore" is valid according to HTML spec.
  -- NOTE The rule is to contain at least 1 "dash" in the name.
  -- tree-sitter HTML parser identies "_xyz" as attribute node
  child.type_keys("<", "my-abc_xyz", ">")
  result = get_lines()

  if ft == "xml" then
    expect.equality(result, { "<my-abc_xyz></my-abc_xyz>" })
  else
    -- FIXME handle/fix this behavior in the plugin?
    expect.equality(result, { "<my-abc_xyz></my-abc>" })
  end
end

T["no-close-malformed-tags"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  child.cmd("startinsert!")

  child.type_keys("<", ">") -- malformed tag with space
  child.cmd("normal! o")

  child.type_keys("<", " ", ">") -- malformed tag with space

  local lines = get_lines()

  -- should not close malformed tag
  expect.equality(lines, {
    "<>",
    "< >",
  })
end

T["insert-before-and-after-gt"] = function(ft, ts_lang)
  init_close_tag(ft, ts_lang)

  -- insert before "< |>" gt
  child.cmd("startinsert!")
  child.type_keys("<", " ", ">")
  child.cmd("normal! 02l")
  child.cmd("startinsert")
  child.type_keys(">")

  -- insert after "< >|" gt
  child.cmd("normal! o")
  child.cmd("startinsert!")
  child.type_keys("<", " ", ">")
  child.cmd("normal! 02l")
  child.cmd("startinsert!")
  child.type_keys(">")

  local lines = get_lines()
  expect.equality(lines, {
    "< >>",
    "< >>"
  })
end

T["doctype"] = function (ft, ts_lang)
  local result = ""
  init_close_tag(ft, ts_lang)

  child.cmd("startinsert!")
  child.type_keys("<", "!doctype html", ">")

  result = get_content()
  expect.equality(result, "<!doctype html>")

  child.type_keys("<", "html", ">")

  result = get_content()
  expect.equality(result, [[<!doctype html><html></html>]])

  child.cmd("%delete")

  child.type_keys("<", "!doctype html", ">")
  child.type_keys("<", "html", " ", [[lang="en"]], ">")

  result = get_content()
  expect.equality(result, [[<!doctype html><html lang="en"></html>]])
end

-- FIXME
T["do-not-close-tag-if-already-closed-on-same-line"] = function(ft, ts_lang)
  MiniTest.skip("should-fix")
  init_close_tag(ft, ts_lang)

  -- delete ">" from opening div and retype it ">" - it should not close the tag again - <div></div></div>
  set_lines([[
    <main>
      <div></div>
      <div> </div>
    </main>
  ]])

  -- set cursor on the ">" of first "div" opening tag
  set_cursor(2, 10)

  -- validate that cursor is set correctly
  local cursor = child.api.nvim_win_get_cursor(winnr())
  local line = child.api.nvim_get_current_line()
  local char = line:sub(cursor[2] + 1, cursor[2] + 1)
  expect.equality(char, ">")

  -- delete ">" and retype
  child.type_keys("x") -- delete ">"
  child.type_keys("i") -- startinsert
  child.type_keys(">") -- retype ">"
  child.cmd("stopinsert")

  -- set cursor on the ">" of second "div" opening tag
  set_cursor(3, 10)
  child.type_keys("x") -- delete ">"
  child.type_keys("i") -- startinsert
  child.type_keys(">") -- retype ">"
  child.cmd("stopinsert")

  local result = get_content()
  expect.equality(result, [[
    <main>
      <div></div>
      <div> </div>
    </main>
  ]])
end

-- TODO
-- T["do-not-close-tag-if-already-closed-on-another-line"] = function(ft, ts_lang)
--   init_close_tag(ft, ts_lang)
--
--   -- delete ">" from opening div and retype it ">" - it should not close the tag again - <div></div></div>
--   set_lines([[
--     <main>
--       <div>
--       </div>
--     </main>
--   ]])
--
--   -- set cursor on the ">" of first div opening tag
--   set_cursor(2, 10)
--
--   -- validate that cursor is set correctly
--   local cursor = child.api.nvim_win_get_cursor(winnr())
--   local line = child.api.nvim_get_current_line()
--   local char = line:sub(cursor[2] + 1, cursor[2] + 1)
--
--   expect.equality(char, ">")
--
--   -- TODO should delete and retype here
--   child.type_keys("x")
--   child.cmd("startinsert!")
--   child.type_keys(">")
--
--   local result = get_content()
--   expect.equality(result, [[
--     <main>
--       <div>
--       </div>
--     </main>
--   ]])
-- end

return T
