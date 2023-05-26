---@diagnostic disable: undefined-global
require("neorg.modules.base")
local ts = require("neorg.modules.external.exec.ts")
local scheduler = require("neorg.modules.external.exec.scheduler")
local renderers = require("neorg.modules.external.exec.renderers")
local running = require("neorg.modules.external.exec.running")

local title = "external.exec"
local module = neorg.modules.create("external.exec")

module.setup = function()
    if vim.fn.isdirectory(running.tmpdir) == 0 then
        vim.fn.mkdir(running.tmpdir, "p")
    end
    return { success = true, requires = { "core.neorgcmd", "core.integrations.treesitter" } }
end

module.config.public = require("neorg.modules.external.exec.config")

module.load = function()
    -- wire up any dependencies
    scheduler.exec_config = module.config.public
    scheduler.start()
    ts.ts = module.required["core.integrations.treesitter"]
    running.exec_config = module.config.public

    -- add subcommands to :Neorg ...
    module.required["core.neorgcmd"].add_commands_from_table({
        exec = {
            args = 1,
            subcommands = {
                cursor = { args = 0, name = "exec.cursor" },
                ["current-file"] = { args = 0, name = "exec.current-file" },
                clear = { args = 0, name = "exec.clear" },
                materialize = { args = 0, name = "exec.materialize" },
            },
        },
    })
end

module.private = {
    enqueue_block_by_index = function(blocknum)
        scheduler.enqueue({
            task_type = "run_block",
            blocknum = blocknum,
            state = nil,
        })
    end,
}

module.public = {
    exec_block_s_under_cursor = function()
        local my_block = ts.current_verbatim_tag()
        if my_block then
            -- NOTE the block will be reevaluated in treesitter by the scheduler, because each result updates the AST
            -- It needs to calculate which block it is,
            -- in case another block is already running & the line number may change
            local code_blocks = ts.find_all_verbatim_blocks("code", true)
            for i, doc_block in ipairs(code_blocks) do
                if my_block == doc_block then
                    module.private.enqueue_block_by_index(i)
                end
            end
        else
            local my_blocks = ts.contained_verbatim_blocks("code", true)
            if not my_blocks or #my_blocks == 0 then
                vim.notify(
                    string.format("This is not a code block (or a heading containing code blocks)"),
                    "warn",
                    { title = title }
                )
            end
            local code_blocks = ts.find_all_verbatim_blocks("code", true)
            for i, allb in ipairs(code_blocks) do
                -- TODO must be the right blocks
                for _, myb in ipairs(my_blocks) do
                    if allb == myb then
                        module.private.enqueue_block_by_index(i)
                        -- vim.notify('found a match inside current block')
                        break -- move to next all_block
                    end
                end
            end
        end
    end,

    exec_current_file = function()
        local code_blocks = ts.find_all_verbatim_blocks("code", true)
        for i, _ in ipairs(code_blocks) do
            -- We really just need the index of each block within the scope.
            -- After a block completes, the next block needs to be found all over again
            module.private.enqueue_block_by_index(i)
        end
    end,

    -- find *all* virtmarks and delete them
    clear_results = function()
        -- TODO put this on the queue?
        vim.api.nvim_buf_clear_namespace(0, renderers.ns, 0, -1)
        local result_blocks = ts.find_all_verbatim_blocks("result")
        -- vim.notify(string.format('found %d', #result_blocks), 'info', {title = title})

        -- iterate backwards to avoid needing to recalculate positions
        for i = #result_blocks, 1, -1 do
            local block = result_blocks[i]
            local start_row = ts.node_carryover_tags_firstline(block)
            local end_row, _, _ = block:end_()
            vim.api.nvim_buf_set_lines(
                0,
                start_row,
                end_row + 1, -- inclusive
                true,
                {}
            )
            -- scheduler.enqueue({
            --   scope = 'wipe_result',
            --   blocknum = i,
            --   do_task = module.private.wipe_result_block,
            -- })
        end
    end,

    -- TODO : pop this onto the queue
    materialize = function()
        local marks = vim.api.nvim_buf_get_extmarks(0, renderers.ns, 0, -1, {})
        for _, mark in ipairs(marks) do
            -- mark is [id,row,col]
            local out = {}
            local curr_task = renderers.extmarks[mark[1]]

            -- vim.notify(string.format('found %s - %d',mark[1], #curr_task.output))
            if curr_task then
                for _, line in ipairs(curr_task.output) do
                    table.insert(out, line[1][1])
                    --vim.notify(string.format('line %s', line[1][1]))
                    --return
                end
                -- vim.notify(string.format('out: %s - %s',mark[2], #out))
                vim.api.nvim_buf_set_lines(curr_task.buf, mark[2] + 1, mark[2] + 1, true, out)
            end
            vim.api.nvim_buf_del_extmark(0, renderers.ns, mark[1])
            renderers.extmarks = {} -- clear it out
        end
        return
    end,
}

module.on_event = function(event)
    if event.split_type[2] == "exec.cursor" then
        vim.schedule(module.public.exec_block_s_under_cursor)
    elseif event.split_type[2] == "exec.current-file" then
        vim.schedule(module.public.exec_current_file)
    elseif event.split_type[2] == "exec.clear" then
        vim.schedule(module.public.clear_results)
    elseif event.split_type[2] == "exec.materialize" then
        vim.schedule(module.public.materialize)
    end
end

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["exec.cursor"] = true,
        ["exec.current-file"] = true,
        ["exec.clear"] = true,
        ["exec.materialize"] = true,
    },
}

return module
