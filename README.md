# neorg-exec

Code block execution for [neorg](https://github.com/nvim-neorg/neorg), similar to [Org Mode's 'eval'](https://orgmode.org/manual/Evaluating-Code-Blocks.html)

neorg-exec captures the results of the code block evaluation and inserts them in the norg file, right after the code block.

The insertion point is after a newline and the ‘RESULTS’ keyword.

neorg-exec creates the ‘RESULTS’ keyword if one is not already there.


This code began with [tamton-aquib's PR](https://github.com/nvim-neorg/neorg/pull/618) - thanks to @tamton-aquib.


## Installation

# 🔧 Installation
First, make sure to pull this plugin down. This plugin does not run any code in of itself. It requires Neorg
to load it first:

You can install it through your favorite plugin manager:

-
  <details>
  <summary><a href="https://github.com/wbthomason/packer.nvim">packer.nvim</a></summary>

  ```lua
  use {
      "nvim-neorg/neorg",
      config = function()
          require('neorg').setup {
              load = {
                  ["core.defaults"] = {},
                  ...
                  ["core.integrations.telescope"] = {}
              },
          }
      end,
      requires = { "nvim-lua/plenary.nvim", "laher/neorg-exec" },
  }
  ```

- <details>
  <summary><a href="https://github.com/junegunn/vim-plug">vim-plug</a></summary>

  ```vim
  Plug 'nvim-neorg/neorg' | Plug 'nvim-lua/plenary.nvim' | Plug 'laher/neorg-exec'
  ```

  You can then put this initial configuration in your `init.vim` file:

  ```vim
  lua << EOF
  require('neorg').setup {
    load = {
        ["core.defaults"] = {},
        ...
        ["external.exec"] = {},
    },
  }
  EOF
  ```

  </details>
- <details>
  <summary><a href="https://github.com/folke/lazy.nvim">lazy.nvim</a></summary>

  ```lua
  require("lazy").setup({
      {
          "nvim-neorg/neorg",
          opts = {
              load = {
                  ["core.defaults"] = {},
                  ...
                  ["external.exec"] = {},
              },
          },
          dependencies = { { "nvim-lua/plenary.nvim" }, { "laher/neorg-exec" } },
      }
  })
  ```

  </details>


# Usage

You can exec a code block with an ex command:

```
:Neorg exec view
```

Or you can bind a key like this:

```lua
local neorg_callbacks = require("neorg.callbacks")

neorg_callbacks.on_event("core.keybinds.events.enable_keybinds", function(_, keybinds)
    -- Map all the below keybinds only when the "norg" mode is active
    keybinds.map_event_to_mode("norg", {
        n = { -- Bind keys in normal mode
            { "<C-c>", "external.exec.view" },
        },
    }, {
        silent = true,
        noremap = true,
    })
end)
```
