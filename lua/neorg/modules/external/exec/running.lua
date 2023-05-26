local ts = require("neorg.modules.external.exec.ts")
local spinner = require("neorg.modules.external.exec.spinner")
local renderers = require("neorg.modules.external.exec.renderers")

local title = "external.exec.running"
local M = {
    exec_config = nil, -- must be injected during setup
    tmpdir = "/tmp/neorg-exec/", -- TODO use io.tmpname? for portability. Or configuation opt?
}

M.session = {

    init = function(task, tx)
        local command = task.state.lang_cfg.repl
        M.spawn(task, command, tx)
    end,

    do_run_block = function(task)
        -- initialize block
        renderers[task.meta.out].init(task)
        local content = table.concat(task.state.code_block.content, "\n")
        task.state.running = true
        task.state.start = os.clock()
        -- vim.notify(string.format("send to running session: %s", content), "info", {title = title})
        vim.api.nvim_chan_send(task.state.jobid, content)

        -- after receiving response (hopefully the whole response)
        task.handle_lines_extra = function()
            renderers[task.meta.out].render_exit(task, nil)
            spinner.shut(task.state.spinner, renderers.ns)
            task.handle_lines_extra = nil
        end
    end,
}

M.oneoff = {
    init = function()
        -- nothing to do
    end,

    do_run_block = function(task, tx)
        -- TODO - use io.tmpfile() / io.tmpname()?
        -- create a temp file and run it
        task.state.temp_filename = M.tmpdir .. task.state.id .. "." .. task.state.ft
        local file = io.open(task.state.temp_filename, "w")
        -- TODO: better error.
        if file == nil then
            return
        end

        local file_content = table.concat(task.state.code_block.content, "\n")
        if
            not vim.tbl_contains(task.state.code_block.parameters, ":main")
            and task.state.lang_cfg.type == "compiled"
        then
            local c = task.state.lang_cfg.main_wrap
            file_content = c:gsub("${1}", file_content)
        end
        file:write(file_content)
        file:close()

        local command = task.state.lang_cfg.cmd:gsub("${0}", task.state.temp_filename)
        M.spawn(task, command, tx)
    end,
}

M.jobopts = function(task, done)
    return {
        stdout_buffered = false,
        env = task.meta.env,

        -- TODO: check colors
        on_stdout = function(_, data)
            M.handle_lines(task, data, "Function")
        end,

        on_stderr = function(_, data)
            M.handle_lines(task, data, "Error")
        end,

        on_exit = function(_, data)
            if data == 0 then
                vim.notify("exit - success", "info", { title = title })
            else
                vim.notify(string.format("exit - non-zero result! %d", data), "warn", { title = title })
            end

            renderers[task.meta.out].render_exit(task, data)
            spinner.shut(task.state.spinner, renderers.ns)
            if task.state.temp_filename then
                vim.fn.delete(task.state.temp_filename)
            end
            task.state.running = false

            done()
        end,
    }
end

M.spawn = function(task, command, done)
    renderers.init(task)
    -- TODO: move to plenary-job?
    task.state.jobid = vim.fn.jobstart(command, M.jobopts(task, done))
end

M.handle_lines = function(task, data, hl)
    if task.state.interrupted then
        vim.fn.jobstop(task.state.jobid)
        return
    end
    renderers[task.meta.out].append(task, data, hl)

    if task.handle_lines_extra ~= nil then
        task.handle_lines_extra()
    end
end

-- prep a task - just to put it onto the queue
M.init_task = function(task)
    -- create an extmark and use its ID as an identifier
    local id = vim.api.nvim_buf_set_extmark(0, renderers.ns, 0, 0, {})

    table.insert(renderers.extmarks, id)

    task.meta = {
        out = "inplace", -- depends on tag. to be updated

    }
    task.state = {
        id = id,
        buf = vim.api.nvim_get_current_buf(),
        interrupted = false,
        jobid = nil,
        temp_filename = nil,
        node = nil,
        code_block = {},
        spinner = nil,
        running = false,
        start = nil,
        output = {}, -- for virtual mode
        linec = 0, -- for normal mode
        charc = 0,
    }

    return true
end

local merge_attributes = function(config_defaults, doc_meta, node_attributes)
  local node_attributes_shallow = {}
  for _, v in ipairs(node_attributes) do
    local n = v.name
    if n == nil then
      vim.notify(vim.inspect(v))
    else
      if string.match(n, 'exec.') then
        n = string.gsub(n, 'exec.', '', 1) -- replace
      end
      node_attributes_shallow[n] = table.concat(v.parameters) -- todo - is concat always ok?
    end
  end
  return vim.tbl_deep_extend("force", config_defaults, doc_meta, node_attributes_shallow)
end

M.validate_meta = function(task)
      if not task.meta.out then
        task.meta.out = "inplace"
      elseif task.meta.out ~= "virtual" and task.meta.out ~= "inplace" then
        task.meta.out = 'inplace'
      end

      if task.meta.enabled == nil then
        task.meta.enabled = true
      elseif task.meta.enabled == "false" or task.meta.enabled == 0 or task.meta.enabled == "0" then
        task.meta.enabled = false
      end

      -- env could be mangled. let's try to unmangle
      if not task.meta.env then
        task.meta.env = {}
      -- I thought of `#exec.env VAR1=1 VAR2=2`, but I don't want to deal with quotes rn
      -- elseif type(task.meta.env) == 'string' then
      --   local s = task.meta.env
      --   task.meta.env = {}
      --   for k, v in string.gmatch(s, "(%w+)=(%w+)") do
      --     task.meta.env[k] = v
      --   end
      elseif type(task.meta.env) == 'table' then
        -- vim.notify('table: ' .. vim.inspect(task.meta))
        for k, v in pairs(task.meta.env) do
          task.meta.env[k] = M.stringify_for_env(v)
        end
      else
        -- ignore non-tables. Strings - nah
        -- vim.notify('type?' .. vim.inspect(task.meta.env))
        task.meta.env = {}
        -- task.meta.env = {}
      end
      -- support `#exec.env.VAR 1` syntax in carryover tags
      for k, v in pairs(task.meta) do
        if k:find('env.', 1, true) == 1 then
          local sub = k:gsub('^env.', '')
          task.meta.env[sub] = M.stringify_for_env(v)
          task.meta[k] = nil -- unset the old `env.x` key
        end
      end
end

M.stringify_for_env = function(v)
  if type(v) == 'string' or type(v) == nil then
    return v
  end
  if type(v) == nil then
    return v
  end
  if type(v) == 'number' then -- if you want a float, stringify it first
    return string.format('%d', v)
  end
  -- TODO maybe resolve funcs in future. I don't see a use case rn
  return vim.inspect(v)
end

M.prep_run_block = function(task)
    local code_blocks = ts.find_all_verbatim_blocks("code", true)
    local node = code_blocks[task.blocknum]
    if not M.init_task(task) then
        return
    end
    local node_info = ts.tag_info(node)
    if not node or not node_info then
        vim.notify(string.format("This is not a code block. %d", task.blocknum), "warn", { title = title })
    elseif node_info.name == "code" then
        -- task.state.block_name = nil


        -- vim.notify(vim.inspect(node_info.parameters))
        local doc_meta = ts.doc_meta(0)
        task.meta = merge_attributes(M.exec_config.default_metadata, doc_meta, node_info.attributes)

        -- vim.notify(vim.inspect(meta), "info", { title = title })
        -- vim.notify(vim.inspect(meta))
        M.validate_meta(task)
        if not task.meta.enabled then
          vim.notify('exec not enabled for this block/doc', 'warn', { title = title })
          return
        end
        -- task.state.block_name = task.meta.name
        if task.meta.name then
            vim.notify(string.format("running code block '%s'", task.meta.name), "info", { title = title })
        else
            vim.notify("running unnamed code block", "info", { title = title })
        end
        task.state["node"] = node
        task.state["code_block"] = node_info

        -- FIX: temp fix remove this!
        -- Amir: I wonder what this fix was for
        node_info["parameters"] = vim.split(node_info["parameters"][1], " ")
        local ft = node_info.parameters[1]
        task.state["ft"] = ft
        task.state.lang_cfg = M.exec_config.lang_cmds[task.state.ft]
        if not task.state.lang_cfg then
            vim.notify("Language not supported currently!", "error", { title = title })
            return
        end
        return true
    elseif node_info.name == "result" then
        vim.notify("This is a result block, not a code block. Look up to the code block!", "warn", { title = title })
    else
        vim.notify(string.format("This is not a code block. %s", node_info.name), "warn", { title = title })
    end
end

return M
