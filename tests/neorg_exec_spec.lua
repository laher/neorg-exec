local running = require("neorg.modules.external.exec.running")
local config = require("neorg.modules.external.exec.config")

describe("running", function()
  local function prep(case)
    vim.cmd ("e " .. case.file)
    return running.prep_run_block(case.task)
    --vim.cmd "Neorg exec current-file"
--    vim.api.nvim_buf_set_lines(0, 0, -1, false, case.lines)
    -- vim.cmd "normal! %y"
    -- return vim.fn.getreg '"'
    --return "foo\n\nb"
    -- return table.concat({#all_blocks, #contained_blocks}, ' ')
  end

  it("blocks_h1", function()
    assert.equal(
      true,
      prep {
        file = '+10 resources/test.norg',
        task = {
          blocknum = 1,
          mconfig = config,
        },
      }
    )
  end)

  it("blocks_h2", function()
    assert.equal(
      true,
      prep {
        file = '+12 resources/test.norg',
        task = {
          blocknum = 1,
          mconfig = config,
        },
      }
    )
  end)
end)
