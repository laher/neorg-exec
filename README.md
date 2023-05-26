# neorg-exec

    **PRE-ALPHA** - breaking changes incoming soon. See Planning, below

`@code` block execution for [neorg](https://github.com/nvim-neorg/neorg),
similar to [Org Mode's 'eval'](https://orgmode.org/manual/Evaluating-Code-Blocks.html).

This code began with
[tamton-aquib's PR](https://github.com/nvim-neorg/neorg/pull/618) -
thanks to @tamton-aquib.

## An example

In a norg file, move the cursor into the code block and execute `:Neorg exec cursor`.

The lua code will run and the `@result` tag will be [re]-generated.

```norg
@code lua
print('hello, neorg')
@end

@result
hello, neorg
@end
```

## Goals and non-goals

This project is super early in development, and working out what it wants to be.
Conceptually, it would be nice to reproduce some of the success of `org-babel`,
but the scope should be limited.

Eventually, Neorg will have its own native `core.exec` module.
Maybe some of this code will be used, maybe not.
For now I'm taking advice from the Neorg team to try and ensure this fits reasonably
into the ecosystem.

### Some goals

* Goal: Support a
[literate programming](https://en.wikipedia.org/wiki/Literate_programming)
use case, but don't try to solve all its problems.
* Goal: execute norg `@code` blocks according to per-language configurations.
* Goal: capture results into `@result` tags, which are themselves
'verbatim ranged tags'.
* Goal: schedule execution appropriately, such that code executions don't
interfere with one another.
* Goal: support extension via public functions.
* Goal: make use of existing modules like `core.tangle`, where appropriate.
* Goal: use a sensible set of tags for affecting the behaviour of code execution.
* Goal: an API to allow for adding runners for different languages.
* Goal: provide some runtime flexibility.
  * Provide support for environment variables, arguments, compilation options,
  some basic error handling.
  * Output handling options - to current-file, an external file, virtual lines.
  * Either execute a code block in its own process, or (for debugging),
  a long-running REPL-style session.

### Non-goals

These non-goals are useful to help define the API, so that people can extend with
their own modules.

* Non-goal: tangling (exporting code to files). See `core.tangle`.
* Non-goal: processing results. This should be done with macros. Maybe another module.
* Non-goal: `org-babel` style interopability between languages and data sources.
Another module might look to reproduce these amazing features.
* Non-goal: a comprehensive platform of language & OS code runners,
containerised runners, all that jazz.

## 🔧 Installation

First, make sure to pull this plugin down.
This plugin does not run any code in of itself.

It requires Neorg to load it first:

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
                  ["external.exec"] = {},
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

## Usage

Given a norg file containing a code block like this:

```norg
@code bash
 print hello
@end
```

You can `exec` the code block under the cursor with an ex command:

```vim
:Neorg exec cursor
```

`cursor` also works on headings. It will execute all code blocks within that
heading section.

To run all blocks in the file, you can use `current-file`.

```vim
:Neorg exec current-file
```

Or you can bind a key like this:

```lua
vim.keymap.set('n', '<localleader>x', ':Neorg exec cursor<CR>', {silent = true}) -- just this block or blocks within heading section
vim.keymap.set('n', '<localleader>X', ':Neorg exec current-file<CR>', {silent = true}) -- whole file
```

_Note: `localleader` is like `leader` but intended more for specific filetypes, such as .norg. You can use `leader` if you prefer)._

### The result

By default, the result will be written into the buffer, directly below the code
tag's `@end` tag:

```norg
#result.start
#result.exit 0.01s 0
@result
hello
@end
```

#### Tags to render the results

Provide some tags to specify how to run the code.

* `exec.name {name}` (or just `name {name}`) - names the block
* `exec.out {virtual|inplace}` (or just `out {virtual|inplace}`) - specifies how
to render the output. (default is `out inplace`).
* `exec.session {sessionid}` (or `session {sessionid}`) - indicates that this block
can be run in a named session. In this way you can run or re-run blocks in the same
interpreter. NOTE that sessions can only apply to languages which are configured
with a `repl_cmd`.
* `exec.env.KEY val` (or `env.KEY val`) - set an environment variable.
* `exec.enabled false` can be used to disable code execution.

```norg
#exec.name helloworld
#exec.out virtual
#exec.env.NAME neorg
@code bash
 print hello $NAME
@end
```

After running a code block with `virtual` rendering, you can use two other subcommands:

* `materialize` to write all virtual text to the file, 'in place'.
* or `clear` to delete the virtual text. `clear` also clears `@result` blocks from
the file.

### Document metadata

Use the `exec` metadata tag, to configure metadata for the whole file.
Note that carrover tags override document metadata.

For example:

```norg
@document.meta
exec: {
  out: virtual
  env: {
    MYVAR: val
  }
}
@end
```

### Configuration

Default configuration settings can be seen in [config.lua](./lua/neorg/modules/external/exec/config.lua).

When you configure `neorg`, you can override some of these settings, like so:

```lua
      ["external.exec"] = {
        config = {
          default_metadata = {
            enabled = false,
            env = {
              NEORG: "rocks"
            },
          },
          lang_cmds = {
            lua = {
              cmd = "luajit ${0}", -- use a different command for running lua
              type = "interpreted",
              repl = nil, -- disable sessions
            },
          },
        }
      },
```

* The `default_metadata` section serves as global defaults for `exec` metadata.
  * `default_metadata` is overridden by document metadata and carryover tags.
  * Note how we set `enabled = false,`. If you set this, you'll need to enable
  `@code` blocks (or whole documents) explicitly.
  * You could also e.g. set some default `env` variables and `out = "virtual"`.
* See the `lang_cmds` section for per-language runtime configuration. A language
type should be either `"interpreted"` or `"compiled"`.

An example of an interpreted language which supports `session`s via a repl:

```lua
lang_cmds = {
    lua = {
        cmd = "lua ${0}",
        type = "interpreted",
        repl = "lua -i",
    },
    ...
}
```

An example for a compiled language, which supports wrapping into a main function.
This example executes some steps before & after running the binary.

```lua
lang_cmds = {
    cpp = {
        cmd = "g++ ${0} && ./a.out && rm ./a.out",
        type = "compiled",
        main_wrap = [[
        #include <iostream>
        int main() {
            ${1}
        }
        ]],
    },
    ...
}
```

## Planning

Not really planning as such. More of a rambling list.

### Some bugs I noticed after importing

* [x] After an invocation fails, there's sometimes an index-out-of-bounds
when you retry.
* Rendering quirks:
  * [x] Results rendering can be a bit unpredictable. Sometimes it gets a bit mangled,
  sometimes it can duplicate the results section.
        * I addressed a lot of the quirks by locating the @result block with treesitter.
  * [ ] Spinner is also a bit funky.
  * [x] `virtual` mode does some weird stuff affecting navigation around the file.
        * seems better now. As good as it can be.

## I'd like to do

* Much of the original PR checklist - see below
* Scheduling:
  * [x] One queue (try plenary.async), one consumer. Single thread executing code.
  * [x] Usually one session & one process at a time, but support multiple workers
  for 'session' support a la org-mode
* UI:
  * [x] ~~Render 'virtual lines' into a popup instead of the buffer.~~ Doesn't
  suit multiple blocks
  * [ ] Maybe spinner could go into the gutter.
  * [x] output handling: 'replace' @result block (instead of 'prepend' another
  @result block)
* Code block tagging, for indicating _how to run_ the code.
  * Similar to org-mode's tagging for [code block environment](https://orgmode.org/manual/Environment-of-a-Code-Block.html) and [result handling](https://orgmode.org/manual/Results-of-Evaluation.html).
  * Options:
    * [-] ~~Consider tags above code blocks like `#exec cache=5m pwd=.. result.tagtype=@`~~
    * [x] Could instead be individual tags per item <- This is @vhyrro's preference.
    * [-] ~~Or, possibly even merge it into the `@code` line ... `@code bash cache=5m`~~
  * [x] env support.
    * [ ] try plenary.job for easy env support. Maybe there are some other
    benefits too.
  * [ ] Caching - similar to org-mode but with cache timeout (plus the hash
  in the result block)
  * [x] Named blocks.
  * [ ] Handling options for stderr, etc. Needs thought - do we want nested tags?
  * [ ] Output type? e.g. `json`. Then results could be syntax-hightlighted just
  like code blocks.
* Results
  * [x] Render in a ranged tag? like `@result\ndone...\n@end`
  (or optionally `|result\n** some norg-formatted output\n|end`)
    * verbatim only, for now. It seems like Macros could fulfil generation
    of norg markup <- @vhyrro's recommendation.
      * [ ] `out=file filename.out`
      * [ ] `out=silent`
      * [ ] What to do about stderr vs stdout? prefixes?
  * [x] Tag with start time? like `#exec.start 2020-01-01T00:11:22.123Z`
  * [ ] Then maybe at the end ... (insert above the @result tag)
    * [x] duration - `#exec.duration_s 1.23s`
    * [x] exit code

* [ ] A way to assess whether a compiler/interpreter is available & feasible.
    e.g. `type -p gcc`. Seems related to cross-platform support.
* [ ] Run multiple blocks at once, within a node, etc. Caching, env variables, macros?
  * [x] whole buffer
  * [x] all blocks under a heading
* [ ] Hopefully, tangle integration.
* [x] file-level tagging (similar to `@code` block tagging)
* Subcommand changes:
  * [x] rename `view` to `virtual`.
  * [x] Restructure, maybe: `:Neorg exec cursor [normal|virtual]`
    `:Neorg exec buf [normal|virtual]` ... not sure yet how to make this extendable.
  * [x] Cursor mode to support 'all code blocks within current norg object'
* [ ] Macro support:
  * [ ] `.exec.call named-block arg arg`
  * [ ] `.exec.result named-result`
  * [ ] some way to address code blocks across files.
  * [ ] some way to chain things together? IDK if this is a good idea, but maybe
        worth thinking about.
* virtual-mode: keep or not keep?
  * Options:
    * [x] Keep
      * it's kinda cool.
      * maybe more suitable for some use cases? like literate programming?
      Hard to assess
    * ~~Not keep~~ ... keeping it.
      * a little bit memory hungry (we need to keep all the lines in a table
      aswell as the virtual lines).
      * The code is a bit more complicated & stateful because of this.
      * Workflow is a bit non-obvious.
      * We could retain virtual lines for stats? and progress reporting?
* Security:
* Safety options:
  * [ ] don't run multiple without confirm?
  * [ ] ~~chroot jails?~~ out of scope
  * [ ] ~~docker-based runners?~~ out of scope
  * [ ] memory limits, timeouts, etc?
  * [ ] killing processes? esp sessions.
  * [x] enabled false, can be configured as a default or a file/block lebel.
    * [ ] (could be the default, maybe?)
* Integration with `core.tangle`:
  * [ ] Respect `core.tangle` tags somehow?
    * [x] Or at least follow the naming conventions. (e.g. `current-file`)
  * [ ] Use `core.tangle` to pre-process code blocks?
    Is that even feasible?

### Planning - some examples

Some examples of what I think a nice tagged code block + results block
could look like ... feedback welcome.

Most of these carryover tags haven't been implemented. But they could be.

```norg
#exec.cache 5m
#exec.pwd=..
#exec.results=replace
@code bash
ls
@end

#exec.start 2020-01-01T00:11:22.123Z hash=0000deadbeef1234
#exec.exit 0 1.23s
@result
dir/
file1.txt
file2.txt
@end
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
  * [x]  ~~view~~ (virtual_lines) renamed to `virtual`
  * [x]  normal (maybe a better command name, normal lines added to buffer.)
* [ ]  add logging?
* [ ]  check for timeout / limit number of output lines.
* [x]  make non-blockable if possible (weird python behaviour)
* [x]  user config options. (done now IMO)
* [x]  set lines to separate files and run.
* [x]  panic messages instead of empty returns.
* [x]  assign state for each running block instead of tracking the current one.
  (will fix spinners and re-execution bugs)
* [x]  code cleanup. (done now IMO)
