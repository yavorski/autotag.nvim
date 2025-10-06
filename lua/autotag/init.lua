---@class AutoTag
---@field setup_autocmd fun(): nil
---@field setup fun(options: AutoTag.Options?): nil
local AutoTag = {}
local Config = require("autotag.config")

---@return nil
function AutoTag.setup_autocmd()
  local augroup = vim.api.nvim_create_augroup("autotag/init-buffer", {})

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = Config.options.filetypes,
    callback = function(event)
      if Config.options.auto_close then
        require("autotag.close-tag").init(event.buf)
      end
      if Config.options.auto_rename then
        require("autotag.rename-tag").init(event.buf)
      end
    end
  })
end

---@param options AutoTag.Options?
---@return nil
function AutoTag.setup(options)
  Config.extend(options)
  AutoTag.setup_autocmd()
end

return AutoTag
