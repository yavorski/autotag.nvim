local AutoTag = {}
local Config = require("autotag.config")

function AutoTag.setup_autocmd()
  local augroup = vim.api.nvim_create_augroup("autotag/init-buffer", {})

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = Config.options.filetypes,
    callback = function(event)
      if Config.options.auto_close then
        require("autotag.close-tag").init(event.buf)
      end
    end
  })
end

function AutoTag.setup(options)
  Config.extend(options)
  AutoTag.setup_autocmd()
end

return AutoTag
