local running = require("neorg.modules.external.exec.running")
local renderers = require("neorg.modules.external.exec.renderers")

renderers.time = function()
    return os.time({ year = 1970, month = 1, day = 1, hour = 0 })
end

describe("metadata", function()
    local function do_test(case)
        -- :e! reopens the file afresh each time
        vim.cmd("e! +" .. case.line .. " " .. case.file)
        local content = vim.api.nvim_buf_get_lines(0, 0, vim.api.nvim_buf_line_count(0), false)
        local before = table.concat(content, "\n")
        running.prep_run_block(case.task)
        renderers.init(case.task)
        local handler = running.jobopts(case.task, function() end)
        handler.on_stdout(_, { "", "hello, world" })
        handler.on_stdout(_, { "!", "", "this is neorg" }) -- simulate handling of incomplete lines
        handler.on_exit(_, 0)

        content = vim.api.nvim_buf_get_lines(0, 0, vim.api.nvim_buf_line_count(0), false)
        local after = table.concat(content, "\n")
        return vim.diff(before, after)
    end

    it("normal", function()
        -- note: this output is currently a little off. There's an extra newline in there.
        -- But when I fix it, I'll update the assertion.
        assert.equal(
            [[@@ -18,0 +19,10 @@
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
                line = 12,
                file = "testdata/metadata.norg",
                task = {
                    blocknum = 1,
                },
            })
        )
    end)

    it("virtual", function()
        -- note: this output is currently a little off. There's an extra newline in there.
        -- But when I fix it, I'll update the assertion.
        assert.equal('',
            do_test({
                line = 19,
                file = "testdata/metadata.norg",
                task = {
                    blocknum = 2,
                },
            })
        )
    end)
end)
