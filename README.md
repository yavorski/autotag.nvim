# autotag.nvim

Neovim plugin to automatically close and rename HTML/XML tags using Treesitter.

> [!NOTE]
> This is a modified fork of [tronikelis/ts-autotag.nvim](https://github.com/tronikelis/ts-autotag.nvim) with added support for filetype aliases.

## Features

* Auto-close HTML/XML tags
* Auto-rename paired opening/closing tags
* Filetype aliases (e.g., `razor` → `html`)
* Per-buffer automatic activation
* Works without overriding any keymaps (no `/` or `>` keymap conflicts)

## Installation

### lazy

Minimal setup with defaults:

```lua
{
  "yavorski/autotag.nvim",
  config = function()
    require("autotag").setup()
  end
}
```

Custom configuration:

```lua
{
  "yavorski/autotag.nvim",
  config = function()
    require("autotag").setup({
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
    })
  end
}
```

## Configuration

| Option             | Type                      | Default                                | Description                              |
| ------------------ | ------------------------- | -------------------------------------- | ---------------------------------------- |
| `filetypes`        | `string[]`                | See above                              | List of filetypes to enable the plugin   |
| `aliases`          | `table<string, string>`   | `{ razor = "html", cshtml = "html" }`  | Map filetypes to parser aliases          |
| `auto_close`       | `boolean`                 | `true`                                 | Enable auto-closing tags                 |
| `auto_rename`      | `boolean`                 | `true`                                 | Enable auto-renaming paired tags         |
| `disable_in_macro` | `boolean`                 | `true`                                 | Disable plugin during macro recording    |
