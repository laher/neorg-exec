local running = require("neorg.modules.external.exec.running")
local renderers = require("neorg.modules.external.exec.renderers")
-- local config = require("neorg.modules.external.exec.config")

renderers.time = function()
    return os.time({ year = 1970, month = 1, day = 1, hour = 0 })
end

describe("running-prep", function()
    local function prep(case)
        vim.cmd("e " .. case.file)
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
            prep({
                file = "testdata/test.norg",
                task = {
                    blocknum = 1,
                },
            })
        )
    end)

    it("blocks_h2", function()
        assert.equal(
            true,
            prep({
                file = "testdata/test.norg",
                task = {
                    blocknum = 1,
                },
            })
        )
    end)
end)

describe("running-handler", function()
    local function do_test(case)
        vim.cmd("e! +" .. case.line .. " " .. case.file)
        local content = vim.api.nvim_buf_get_lines(0, 0, vim.api.nvim_buf_line_count(0), false)
        local before = table.concat(content, "\n")
        running.prep_run_block(case.task)
        renderers.init(case.task)
        local jobopts = running.jobopts(case.task, function() end)
        jobopts.on_stdout(_, { "", "hello, world" })
        jobopts.on_stdout(_, { "!", "", "this is neorg" }) -- simulate handling of incomplete lines
        jobopts.on_exit(_, 0)

        content = vim.api.nvim_buf_get_lines(0, 0, vim.api.nvim_buf_line_count(0), false)
        local after = table.concat(content, "\n")
        return vim.diff(before, after)
    end

    it("normal", function()
        -- note: this output is currently a little off. There's an extra newline in there.
        -- But when I fix it, I'll update the assertion.
        assert.equal(
            [[@@ -17,0 +18,10 @@
+#exec.start 1970.01.01T00.00.00NZST
+#exec.end 0.0000s 0
+@result
+
+hello, world!
+
+
+this is neorg
+@end
+
]],
            do_test({
                line = 10,
                file = "testdata/test.norg",
                task = {
                    blocknum = 1,
                },
            })
        )
    end)

    it("virtual", function()
        assert.equal(
            "",
            do_test({
                line = 12,
                file = "testdata/test.norg",
                task = {
                    blocknum = 2,
                },
            })
        )
    end)
end)
