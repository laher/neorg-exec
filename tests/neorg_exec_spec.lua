
local ts = require("neorg.modules.external.exec.ts")
local renderers = require("neorg.modules.external.exec.renderers")

describe("ts", function()
  local function ts_happy(case)
    vim.cmd ("e " .. case.file)
    local all_blocks = ts.find_all_verbatim_blocks('code', true)
    local contained_blocks = ts.contained_verbatim_blocks('code', true)
    --vim.cmd "Neorg exec current-file"
--    vim.api.nvim_buf_set_lines(0, 0, -1, false, case.lines)
    -- vim.cmd "normal! %y"
    -- return vim.fn.getreg '"'
    --return "foo\n\nb"
    return table.concat({#all_blocks, #contained_blocks}, ' ')
  end

  it("blocks_h1", function()
    assert.equal(
      "3 3",
      ts_happy {
        file = '+10 resources/test.norg',
      }
    )
  end)

  it("blocks_h2", function()
    assert.equal(
      "3 1",
      ts_happy {
        file = '+12 resources/test.norg',
      }
    )
  end)
end)
