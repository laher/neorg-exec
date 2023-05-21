-- I copied this from nvim-treesitter just as a sanity check

local tsutils = require "nvim-treesitter.ts_utils"

describe("update_selection", function()
  local function get_updated_selection(case)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, case.lines)
    tsutils.update_selection(0, case.node, case.selection_mode)
    vim.cmd "normal! y"
    return vim.fn.getreg '"'
  end

  it("charwise1", function()
    assert.equal(
      get_updated_selection {
        lines = { "foo", "", "bar" },
        node = { 0, 0, 2, 1 },
        selection_mode = "v",
      },
      "foo\n\nb"
    )
  end)
end)
