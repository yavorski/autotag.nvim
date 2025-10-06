---@class AutoTag.Options
---@field filetypes? string[]
---@field aliases? table<string, string>
---@field auto_close? boolean
---@field auto_rename? boolean
---@field disable_in_macro? boolean

---@class Config
---@field options AutoTag.Options
---@field extend fun(options: AutoTag.Options?): AutoTag.Options
local Config = {}

---@type AutoTag.Options
Config.options = {
  filetypes = {
    "xml",
    "html",
    "templ",
    "htmlangular",
    "typescriptreact",
    "javascriptreact",
  },
  aliases = {
    razor = "html",
    cshtml = "html",
  },
  auto_close = true,
  auto_rename = true,
  disable_in_macro = true,
}

---@param options AutoTag.Options?
---@return AutoTag.Options
function Config.extend(options)
  Config.options = vim.tbl_deep_extend("force", Config.options, options or {})

  for ft, _ in pairs(Config.options.aliases) do
    if not vim.list_contains(Config.options.filetypes, ft) then
      table.insert(Config.options.filetypes, ft)
    end
  end

  return Config.options
end

return Config
