local Config = {}

Config.defaults = {
  filetypes = {
    "xml",
    "html",
    -- "templ",
    -- "htmlangular",
    -- "typescript",
    -- "javascript",
    -- "typescriptreact",
    -- "javascriptreact",
  },

  aliases = {
    -- razor = "html",
    -- cshtml = "html",
    -- htmlangular = "html",
  },

  auto_close = true,
  auto_rename = true,
  disable_in_macro = true,
}

Config.options = {}

function Config.extend(options)
  options = vim.tbl_deep_extend("force", Config.defaults, options or {})

  for ft, _ in pairs(options.aliases) do
    if not vim.tbl_contains(options.filetypes, ft) then
      table.insert(options.filetypes, ft)
    end
  end

  Config.options = options
  return Config.options
end

return Config
