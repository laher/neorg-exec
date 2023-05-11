---@diagnostic disable: undefined-global
require("neorg.modules.base")
local spinner = require("neorg.modules.external.exec.spinner")
local title = "external.exec"
local module = neorg.modules.create("external.exec")
module.setup = function()
    if vim.fn.isdirectory(module.private.tmpdir) == 0 then
        vim.fn.mkdir(module.private.tmpdir, "p")
    end
    return { success = true, requires = { "core.neorgcmd", "core.integrations.treesitter" } }
end

module.load = function()
    module.required["core.neorgcmd"].add_commands_from_table({
        exec = {
            args = 1,
            subcommands = {
                cursor = { args = 0, name = "exec.cursor" },
                buf = { args = 0, name = "exec.buf" },
                hide = { args = 0, name = "exec.hide" },
                materialize = { args = 0, name = "exec.materialize" },
            },
        },
    })
end

module.config.public = require("neorg.modules.external.exec.config")
module.config.private = {}

module.private = {
    tasks = {},

    ns = vim.api.nvim_create_namespace("exec"),

    virtual = {
        init = function(id)
            local curr_task = module.private.tasks[id]
            curr_task.spinner = spinner.start(curr_task, module.private.ns)

            -- Fix for re-execution
            -- if not vim.tbl_isempty(curr_task.output) then
                -- curr_task.output = {}
            -- end

            curr_task.output = {
              { { "", "Keyword" } },
              { { os.date("#exec.start %Y-%m-%dT%H:%M:%S%Z", os.time()), "Keyword" } },
              { { "@result", "Keyword" } },
              { { "", "Function" } },
            }

            module.private.virtual.update(id)
            return id
        end,

        update = function(id)
            local curr_task = module.private.tasks[id]
            vim.api.nvim_buf_set_extmark(
                curr_task.buf,
                module.private.ns,
                curr_task.code_block["end"].row,
                0,
                { id = id, virt_lines = curr_task.output }
            )
        end,
    },

    normal = {
        init = function(id)
            local curr_task = module.private.tasks[id]
            curr_task.spinner = spinner.start(curr_task, module.private.ns)
            -- overwrite it
            -- locate existing result block with treesitter and delete it
            module.private.clear_next_result_tag(curr_task.buf, curr_task.node)

            -- local ns = p:next_named_sibling()

            if not vim.tbl_isempty(curr_task.output) then
								-- local linecount = vim.api.nvim_buf_line_count(0)
								-- local lastline = curr_task.code_block["end"].row + 1 + #curr_task.output + 1
								-- if lastline > linecount then
								-- 	lastline = linecount
								-- end
        --         vim.api.nvim_buf_set_lines(
        --             curr_task.buf,
        --             curr_task.code_block["end"].row + 1,
								-- 		lastline,
        --             true,
        --             {}
        --         )
                -- initialise
                curr_task.output = {}
            end
            curr_task.output = { "", string.format("%s",os.date("#exec.start %Y-%m-%dT%H:%M:%S%Z", os.time())), "@result", "" }

            vim.api.nvim_buf_set_lines(
                curr_task.buf,
                curr_task.code_block["end"].row + 1,
                curr_task.code_block["end"].row + 1,
                true,
                curr_task.output
            )
            -- table.insert(curr_task.output, "")
            -- table.insert(curr_task.output, os.date("#exec.start %Y-%m-%dT%H:%M:%S%Z", os.time()))
            -- table.insert(curr_task.output, "@result")
            -- table.insert(curr_task.output, "@end")

            -- for i, line in ipairs(curr_task.output) do
            --     vim.api.nvim_buf_set_lines(
            --         curr_task.buf,
            --         curr_task.code_block["end"].row + module.private.header + i,
            --         curr_task.code_block["end"].row + module.private.header + i,
            --         true,
            --         { line }
            --     )
            -- end
        end,

        update = function(id, line)
            local curr_task = module.private.tasks[id]
            vim.api.nvim_buf_set_lines(
                curr_task.buf,
                curr_task.code_block["end"].row + #curr_task.output,
                curr_task.code_block["end"].row + #curr_task.output,
                true,
                { line }
            )
        end,
        update_line = function(id, line, charnum)
            local curr_task = module.private.tasks[id]
            vim.api.nvim_buf_set_text(
                curr_task.buf,
                curr_task.code_block["end"].row + #curr_task.output,
                charnum,
                curr_task.code_block["end"].row + #curr_task.output,
                charnum,
                -- true,
                { line }
            )
        end,
    },

    init_cursor = function()
        -- IMP: check for existng marks and return if it exists.
        local cr, _ = unpack(vim.api.nvim_win_get_cursor(0))

        for id_idx, id_cfg in pairs(module.private.tasks) do
            -- if id_cfg.code_block then
            --   print()
            -- end
            local code_start, code_end = id_cfg.code_block["start"].row + 1, id_cfg.code_block["end"].row + 1

            if code_start <= cr and code_end >= cr then
                return id_idx
            end
        end
        return module.private.init_task()
    end,

    init_task = function()
        local id = vim.api.nvim_buf_set_extmark(0, module.private.ns, 0, 0, {})

        module.private.tasks[id] = {
            buf = vim.api.nvim_get_current_buf(),
            output = {},
            interrupted = false,
            jobid = nil,
            temp_filename = nil,
            node = nil,
            code_block = {},
            spinner = nil,
            running = false,
            start = nil,
        }

        return id
    end,

    handle_lines = function(id, data, hl)
        if module.private.tasks[id].interrupted then
            vim.fn.jobstop(module.private.tasks[id].jobid)
            return
        end

        local curr_task = module.private.tasks[id]
        for i, line in ipairs(data) do
          if i == 1 and #curr_task.output > 0 then -- continuation of previous chunk (this is how unbuffered jobs work in nvim)
            local existing = curr_task.output[#curr_task.output]
            if existing then
              if module.private.mode == "virtual" then
                local eline = existing[1][1]
                curr_task.output[#curr_task.output][1][1] =  eline .. line
                module.private.virtual.update(id)
              else
                curr_task.output[#curr_task.output] =  existing .. line
                module.private.normal.update_line(id, line, #existing)
              end
            -- else something is wrong
            end
          else
            if module.private.mode == "virtual" then
              table.insert(curr_task.output, { { line, hl } })
              module.private.virtual.update(id)
            else
              table.insert(curr_task.output, line)
              module.private.normal.update(id, line)
            end
          end
        end
    end,

    spawn = function(id, command)
        local mode = module.private.mode

        module.private[mode == "virtual" and "virtual" or "normal"].init(id)

        module.private.tasks[id].running = true
        module.private.tasks[id].start = os.clock()
        module.private.tasks[id].jobid = vim.fn.jobstart(command, {
            stdout_buffered = false,

            -- TODO: check colors
            on_stdout = function(_, data)
                module.private.handle_lines(id, data, "Function")
            end,

            on_stderr = function(_, data)
                module.private.handle_lines(id, data, "Error")
            end,

            on_exit = function(_, data)
                if data == 0 then
                  vim.notify("exec - success", "info", {title = title})
                else
                  vim.notify(string.format("exec - non-zero result! %d", data), "warn", {title = title})
                end
                local exec_exit = string.format("#exec.exit %s %0.4fs", data, os.clock() - module.private.tasks[id].start)
                local curr_task = module.private.tasks[id]
                if module.private.mode == "virtual" then
                    table.insert(curr_task.output, 3, { { exec_exit, "Keyword" } })
                    table.insert(curr_task.output, { { "@end", "Keyword" } })
                    module.private.virtual.update(id)
                else
                    vim.api.nvim_buf_set_lines(
                        curr_task.buf,
                        curr_task.code_block["end"].row + 3,
                        curr_task.code_block["end"].row + 3,
                        true,
                        { exec_exit }
                    )
                    table.insert(curr_task.output, { { "@end", "Keyword" } })
                    module.private.normal.update(id, "@end")
                end

                spinner.shut(module.private.tasks[id].spinner, module.private.ns)
                vim.fn.delete(module.private.tasks[id].temp_filename)
                module.private.tasks[id].running = false
                module.private.take_from_queue() -- process any more work to do
            end,
        })
    end,
    tmpdir = "/tmp/neorg-exec/", -- TODO use io.tmpname? for portability
    -- mode = "normal",
    mode = nil,

    current_node = function()
        local ts = module.required["core.integrations.treesitter"].get_ts_utils()
        local node = ts.get_node_at_cursor(0, true)
        local p = module.required["core.integrations.treesitter"].find_parent(node, "^ranged_verbatim_tag$")
        return p
    end,

    find_next_sibling = function(node, types)
        local _node = node:next_sibling()

        while _node do
            if type(types) == "string" then
                if _node:type():match(types) then
                    return _node
                end
            elseif vim.tbl_contains(types, _node:type()) then
                return _node
            end

            _node = _node:next_sibling()
        end
    end,

    find_all_code_nodes = function()
        local buffer = 0
        local parsed_document_metadata = module.required["core.integrations.treesitter"].get_document_metadata(buffer)

        if vim.tbl_isempty(parsed_document_metadata) or not parsed_document_metadata.tangle then
            parsed_document_metadata = {
                exec = {},
            }
        end

        local document_root = module.required["core.integrations.treesitter"].get_document_root(buffer)

        local options = {
            languages = {},
            scope = parsed_document_metadata.exec.scope or "all", -- "all" | "tagged" | "main"
        }


        local query_str = neorg.lib.match(options.scope)({
            _ = [[
                (ranged_verbatim_tag
                    name: (tag_name) @_name
                    (#eq? @_name "code")
                    (tag_parameters
                       .
                       (tag_param) @_language)) @tag
            ]],
            tagged = [[
                (ranged_verbatim_tag
                    [(strong_carryover_set
                        (strong_carryover
                          name: (tag_name) @_strong_carryover_tag_name
                          (#eq? @_strong_carryover_tag_name "exec.name")))
                     (weak_carryover_set
                        (weak_carryover
                          name: (tag_name) @_weak_carryover_tag_name
                          (#eq? @_weak_carryover_tag_name "exec.name")))]
                  name: (tag_name) @_name
                  (#eq? @_name "code")
                  (tag_parameters
                    .
                    (tag_param) @_language)) @tag
            ]],
        })


        local query = neorg.utils.ts_parse_query("norg", query_str)
        local nodes = {}

        for id, node in query:iter_captures(document_root, buffer, 0, -1) do
            local capture = query.captures[id]
             if capture == "tag" then
               table.insert(nodes, node)
             end
        end
        return nodes

    end,

    node_info = function(p)
        -- TODO: Add checks here
        local cb = module.required["core.integrations.treesitter"].get_tag_info(p, true)
        if not cb then
            vim.notify("Not inside a tag!", "warn", {title = title})
            return
        end
        return cb
    end,

    node_carrover_tags = function(p)
        local tags = {}
        --local p = p:prev_named_sibling():prev_named_sibling()
        for child, _ in p:iter_children() do
            if child:type() == "strong_carryover_set" then
                for child2, _ in child:iter_children() do
                    if child2:type() == "strong_carryover" then
                        local cot = module.required["core.integrations.treesitter"].get_tag_info(child2, true)
                        tags[cot.name] = cot.parameters
                        -- vim.notify(string.format("%s: %s", cot.name, table.concat(cot.parameters, '-')))
                    end
                end
            end
        end
        return tags
    end,

    base = function(id, node, node_info)

        if node_info.name == "code" then
            -- default is 'normal'
            module.private.mode = "normal"
            local name

            local tags = module.private.node_carrover_tags(node)
            for tag, params in pairs(tags) do
                local paramS = table.concat(params)
                if tag == "exec.name" then
                    name = paramS
                    -- vim.notify(params)
                elseif tag == "exec.render" then
                    -- vim.notify(string.format("result rendering is %s", paramS))
                    if paramS == "virtual" then
                        module.private.mode = "virtual"
                    end
                end
            end
            if name then
              vim.notify(string.format("running code block '%s'", name), "info", {title = title})
            else
              vim.notify("running unnamed code block", "info", {title = title})
            end
            module.private.tasks[id]["code_block"] = node_info
            module.private.tasks[id]["node"] = node

            -- FIX: temp fix remove this!
            -- Amir: I wonder what this fix was for
            node_info["parameters"] = vim.split(node_info["parameters"][1], " ")
            local ft = node_info.parameters[1]

            -- TODO - use io.tmpfile() / io.tmpname()?
            module.private.tasks[id].temp_filename = module.private.tmpdir .. id .. "." .. ft

            local lang_cfg = module.config.public.lang_cmds[ft]
            if not lang_cfg then
                vim.notify("Language not supported currently!", "error", {title = title})
                return
            end

            local file = io.open(module.private.tasks[id].temp_filename, "w")
            -- TODO: better error.
            if file == nil then
                return
            end

            local file_content = table.concat(node_info.content, "\n")
            if not vim.tbl_contains(node_info.parameters, ":main") and lang_cfg.type == "compiled" then
                local c = lang_cfg.main_wrap
                file_content = c:gsub("${1}", file_content)
            end
            file:write(file_content)
            file:close()

            local command = lang_cfg.cmd:gsub("${0}", module.private.tasks[id].temp_filename)
            module.private.spawn(id, command)
        elseif node_info.name == "result" then
            vim.notify("This is a result block, not a code block. Look up to the code block!", "warn", {title = title})
        else
            vim.notify(string.format("This is not a code block. %s", node_info.name), "warn", {title = title})
        end
    end,

    queue = {

    },


    take_from_queue = function()
      if #module.private.queue > 0 then
        local code_blocks = module.private.find_all_code_nodes()
        local current_item = table.remove(module.private.queue, 1)
        -- TODO
        -- if current_item[2] == "cursor" then find blocks within the cursor's object
        local code_block = code_blocks[current_item[1]]
        local id = module.private.init_task()
        local code_block_info = module.private.node_info(code_block)
        module.private.base(id, code_block, code_block_info)
      end
    end,

    clear_next_result_tag = function(buf, p)
            local s = module.private.find_next_sibling(p, "^ranged_verbatim_tag$")

            if s then
              local sinf = module.private.node_info(s)
              -- needs to be a result before any other rbt's
              if sinf.name  == "result" then
                vim.api.nvim_buf_set_lines(
                  buf,
                  sinf.start.row-1, -- assume headers
                  sinf["end"].row+1, -- assume footer
                  true,
                  {}
                )
              end
            end
    end,

}

module.public = {
    -- TODO - all blocks in a section
    do_code_block_under_cursor = function()
        local id = module.private.init_cursor()
        local code_block = module.private.current_node()
        local code_block_info = module.private.node_info(code_block)
        if not code_block_info then
            return
        end
        module.private.base(id, code_block, code_block_info)
    end,

    -- TODO - make this efficient
    do_buf = function()
      -- we really just need the count
      local code_blocks = module.private.find_all_code_nodes()
      for i, _ in ipairs(code_blocks) do
        table.insert(module.private.queue, {i, "buf"})
      end
      module.private.take_from_queue()
      --vim.notify("exec whole buffer not supported yet", "warn", {title = title})
    end,


    hide = function()
        -- HACK: Duplication
        local cr, _ = unpack(vim.api.nvim_win_get_cursor(0))

        for id_idx, id_cfg in pairs(module.private.tasks) do
            local code_start, code_end = id_cfg.code_block["start"].row + 1, id_cfg.code_block["end"].row + 1

            if code_start <= cr and code_end >= cr then
                if module.private.mode == "virtual" then
                    vim.api.nvim_buf_del_extmark(0, module.private.ns, id_idx)
                else
                    vim.api.nvim_buf_set_lines(0, code_end, code_end + #id_cfg["output"], false, {})
                end

                module.private.tasks[id_idx] = nil
                return
            end
        end
    end,

    materialize = function()
        local cr, _ = unpack(vim.api.nvim_win_get_cursor(0))

        -- FIX: DUPLICATION AGAIN!!!
        for id_idx, id_cfg in pairs(module.private.tasks) do
            local code_start = id_cfg.code_block["start"].row + 1
            local code_end = id_cfg.code_block["end"].row + 1

            if code_start <= cr and code_end >= cr then
                local curr_task = module.private.tasks[id_idx]

                -- clear virtual lines
                vim.api.nvim_buf_set_extmark(
                    curr_task.buf,
                    module.private.ns,
                    curr_task.code_block["end"].row,
                    0,
                    { id = id_idx, virt_lines = nil }
                )
                module.private.clear_next_result_tag(curr_task.buf, curr_task.node)

                local t = vim.tbl_map(function(line)
                    return line[1][1]
                end, curr_task.output)

                for i, line in ipairs(t) do
                    vim.api.nvim_buf_set_lines(
                        curr_task.buf,
                        curr_task.code_block["end"].row + i,
                        curr_task.code_block["end"].row + i,
                        true,
                        { line }
                    )
                end

                module.private.mode = "normal"
            end
        end
    end,
}

module.on_event = function(event)
    if event.split_type[2] == "exec.cursor" then
        vim.schedule(module.public.do_code_block_under_cursor)
    elseif event.split_type[2] == "exec.buf" then
        vim.schedule(module.public.do_buf)
    elseif event.split_type[2] == "exec.hide" then
        vim.schedule(module.public.hide)
    elseif event.split_type[2] == "exec.materialize" then
        vim.schedule(module.public.materialize)
    end
end

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["exec.cursor"] = true,
        ["exec.buf"] = true,
        ["exec.hide"] = true,
        ["exec.materialize"] = true,
    },
}

return module
