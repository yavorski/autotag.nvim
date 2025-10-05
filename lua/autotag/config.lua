local Config = {}

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
