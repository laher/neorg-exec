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
:Neorg exec normal
```

Or you can bind a key like this:

```lua
vim.keymap.set('n', '<C-c>', ':Neorg exec normal<CR>', {silent = true}) -- search file
```

You can probably do it with `neorg_callbacks` but I haven't got there yet.


# TODO

## Some bugs I noticed after importing

 * [ ] After an invocation fails, there's a null pointer when you try again
 * [ ] Results rendering can be a bit unpredictable. Sometimes it gets a bit mangled, sometimes it can duplicate the results section. Spinner is also a bit funky.
 * [ ] Virtual mode does some weird stuff sometimes, affecting navigation.

## I'd like to do

 * [ ] Render 'virtual lines' into a popup instead of the buffer. ... Maybe spinner could go into the gutter.
 * [ ] Code block tagging, for indicating _how to run_ the code. Similar to org-mode's caching indicators.
    * [ ] Consider tags above code blocks like `#exec cache=5m pwd=.. result.tagtype=@`
    * [ ] Could instead be individual tags per item,
    * [ ] Or, possibly even merge it into the `@code` line ... `@code bash cache=5m`
 * [ ] Results
    * [ ] Render in a ranged tag? like `@result\ndone...\n@end` (or optionally `|result\n** some norg-formatted output\n|end`)
    * [ ] Tag with timings and result code? like `#exec.result.start time=2020-01-01T00:11:22.123Z codehash=0000deadbeef1234`
    * [ ] Then maybe at the end, something like `#exec.result.finish duration=1.23s exitcode=0`
 * [ ] A nice way to assess whether a compiler/interpreter is available & feasible. e.g. `type -p gcc`. Seems related to cross-platform support.
 * [ ] Run a file at once. Caching, env variables, macros?

### Planning - some examples

Some examples of what I think a nice tagged code block + results block could look like ... feedback welcome.

1. Generating some random output - put it in a verbatim range

```norg
#exec cache=5m pwd=..
@code bash
ls
@end

+exec.result.start time=2020-01-01T00:11:22.123Z codehash=0000deadbeef1234
@result
dir/
file1.txt
file2.txt
@end
+exec.result.finish duration=1.23s exitcode=0
 ```

2. Generating some neorg output - put it in a standard range...

```norg
#exec cache=24h result.tagtype=|
@code bash
./generate-todos-from-gmail
@end

+exec.result.start time=2020-01-01T00:11:22.123Z codehash=0000deadbeef1234
|result
*** todos
 - (?) Reply to daily report
 - ( ) Breakfast with Tiffany
 - ( ) Cook the ice-cream
|end
+exec.result.finish duration=1.23s exitcode=0
 ```

## 'Possible todos' from original PR

See [https://github.com/nvim-neorg/neorg/pull/618#issue-1402358683](Pull Request)

 * [ ]  cross platform support.
 * [x]  spinner for running block.
 * [ ]  run for
   * [x]  compiled (c, cpp, rust, etc)
     * [ ]  check extra parameters for wrapping in main function? (+ named blocks)
   * [x]  interpreted (python, lua, bash, etc)
 * [x]  subcommands
   * [x]  view (virtual_lines)
   * [x]  normal (maybe a better command name, normal lines added to buffer.)
 * [ ]  add logging?
 * [ ]  check for timeout / limit number of output lines.
 * [x]  make non-blockable if possible (weird python behaviour)
 * [ ]  user config options.
 * [x]  set lines to separate files and run.
 * [x]  panic messages instead of empty returns.
 * [x]  assign state for each running block instead of tracking the current one. (will fix spinners and re-execution bugs)
 * [ ]  code cleanup.
