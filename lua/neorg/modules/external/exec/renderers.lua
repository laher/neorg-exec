local ts = require("neorg.modules.external.exec.ts")
local spinner = require("neorg.modules.external.exec.spinner")
local M = {
    virtual = {},
    inplace = {},
    ns = vim.api.nvim_create_namespace("exec"),
    extmarks = {}, -- a sequence of virtual text blocks
}

-- replace this during testing
M.time = function()
    return os.time()
end

M.startline = function()
    -- eesh you can't use - or :, otherwise norg won't parse it
    return os.date("#exec.start %Y.%m.%dT%H.%M.%S%Z", M.time())
end

M.endline = function(task, exit_code)
    local endl = string.format("#exec.end %0.4fs", M.time() - task.state.start)
    if exit_code ~= nil then -- nil is for sessions
        endl = endl .. " " .. exit_code -- non-nil is for non-sessions
    end
    return endl
end

M.init = function(task)
    M[task.meta.out].init(task)
    task.state.running = true
    task.state.start = M.time()
end

M.virtual.init = function(task)
    M.virtual.clear_next_result_tag(task.state.buf, task.state.node)
    task.state.spinner = spinner.start(task.state, M.ns)

    -- Fix for re-execution
    -- if not vim.tbl_isempty(curr_task.output) then
    -- curr_task.output = {}
    -- end

    task.state.output = {
        { { "", "Keyword" } },
        { { M.startline(), "Keyword" } },
        { { "@result", "Keyword" } },
        { { "", "Function" } },
    }

    M.extmarks[task.state.id] = task.state -- for materializing later
    M.virtual.update(task)
    return task.state.id
end

M.virtual.clear_next_result_tag = function(buf, p)
    local pinf = ts.tag_info(p)
    vim.api.nvim_buf_clear_namespace(buf, M.ns, pinf["end"].row, pinf["end"].row + 1)
end

M.virtual.append = function(task, data, hl)
    for i, line in ipairs(data) do
        if i == 1 and #task.state.output > 0 then -- continuation of previous chunk (this is how unbuffered jobs work in nvim)
            local existing = task.state.output[#task.state.output]
            if existing then
                local eline = existing[1][1]
                task.state.output[#task.state.output][1][1] = eline .. line
                M.virtual.update(task)
                -- else something is wrong
            end
        else
            table.insert(task.state.output, { { line, hl } })
            M.virtual.update(task)
        end
    end
end

M.virtual.update = function(task)
    vim.api.nvim_buf_set_extmark(
        task.state.buf,
        M.ns,
        task.state.code_block["end"].row,
        0,
        { id = task.state.id, virt_lines = task.state.output }
    )
end

M.virtual.render_exit = function(task, exit_code)
    table.insert(task.state.output, 3, { { M.endline(task, exit_code), "Keyword" } })
    -- table.insert(curr_task.output, { { "@end", "Keyword" } })
    M.virtual.append(task, { "@end" }, "Keyword")
    M.virtual.update(task)
end

M.inplace.init = function(task)
    task.state.spinner = spinner.start(task.state, M.ns)
    -- overwrite it
    -- locate existing result block with treesitter and delete it
    M.inplace.clear_next_result_tag(task.state.buf, task.state.node)
    if not vim.tbl_isempty(task.state.output) then
        task.state.output = {}
    end
    -- first line is ignored
    local output = { "", "", M.startline(), "@result", "" }

    M.inplace.append(task, output)

    local linec = task.state.linec
    local charc = task.state.charc
    M.inplace.append(task, { "", "", "@end" })
    task.state.linec = linec
    task.state.charc = charc -- don't overwrite @end
end

M.inplace.clear_next_result_tag = function(buf, p)
    local s = ts.find_next_sibling(p, "^ranged_verbatim_tag$")

    if s then
        local sinf = ts.tag_info(s)
        -- needs to be a result before any other rbt's
        if sinf.name == "result" then
            vim.api.nvim_buf_set_lines(
                buf,
                sinf.start.row - 1, -- assume headers
                sinf["end"].row + 1, -- assume footer
                true,
                {}
            )
        end
    end
end

M.inplace.append = function(task, lines)
    if #lines < 1 then
        -- vim.notify('nothing')
        -- nothing. unexpected!
        return
    end
    if #lines == 1 and lines[0] == "" then
        -- vim.notify('eof')
        -- EOF
        return
    end
    local curr_task = task.state
    -- vim.notify(string.format('rcv %d lines', #lines))
    -- first line should be joined with existing last line if it's non-empty
    local first_line = table.remove(lines, 1)
    if first_line ~= "" then
        vim.api.nvim_buf_set_text(
            curr_task.buf,
            curr_task.code_block["end"].row + curr_task.linec,
            curr_task.charc,
            curr_task.code_block["end"].row + curr_task.linec,
            curr_task.charc,
            { first_line }
        )
        curr_task.linec = curr_task.linec + 1
    end
    -- other lines ... just append at once
    if #lines > 0 then
        vim.api.nvim_buf_set_lines(
            curr_task.buf,
            curr_task.code_block["end"].row + curr_task.linec + 1,
            curr_task.code_block["end"].row + curr_task.linec + 1,
            true,
            lines
        )
        -- length of last line
        curr_task.charc = #lines[#lines]
    else
        curr_task.charc = curr_task.charc + #first_line
    end
    curr_task.linec = curr_task.linec + #lines
end

M.inplace.render_exit = function(task, exit_code)
    -- include an extra prefix line to indicate last line was complete
    -- M.inplace.append(task, { "", "@end", "" })
    -- insert directly
    vim.api.nvim_buf_set_lines(
        task.state.buf,
        task.state.code_block["end"].row + 3,
        task.state.code_block["end"].row + 3,
        true,
        { M.endline(task, exit_code) }
    )
end

return M
