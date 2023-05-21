local ts = require("neorg.modules.external.exec.ts")
local spinner = require("neorg.modules.external.exec.spinner")
local renderers = require("neorg.modules.external.exec.renderers")

local title = "external.exec.running"
local M = {
    tmpdir = "/tmp/neorg-exec/", -- TODO use io.tmpname? for portability. Or configuation opt?
}

M.session = {

    init = function(task, tx)
        local command = task.state.lang_cfg.repl
        M.spawn(task, command, tx)
    end,

    do_run_block = function(task)
        -- initialize block
        renderers[task.state.outmode].init(task)
        local content = table.concat(task.state.code_block.content, "\n")
        task.state.running = true
        task.state.start = os.clock()
        -- vim.notify(string.format("send to running session: %s", content), "info", {title = title})
        vim.api.nvim_chan_send(task.state.jobid, content)

        -- after receiving response (hopefully the whole response)
        task.handle_lines_extra = function()
            renderers[task.state.outmode].render_exit(task, nil)
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

M.handler = function(task, done)
    return {
        stdout_buffered = false,

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

            renderers[task.state.outmode].render_exit(task, data)
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
    task.state.jobid = vim.fn.jobstart(command, M.handler(task, done))
end


M.handle_lines  = function(task, data, hl)
  if task.state.interrupted then
    vim.fn.jobstop(task.state.jobid)
    return
  end
  renderers[task.state.outmode].append(task, data, hl)

  if task.handle_lines_extra ~= nil then
    task.handle_lines_extra()
  end
end


-- prep a task - just to put it onto the queue
M.init_task = function(task)
  -- create an extmark and use its ID as an identifier
  local id = vim.api.nvim_buf_set_extmark(0, renderers.ns, 0, 0, {})

  table.insert(renderers.extmarks, id)

  task.state = {
    id = id,
    buf = vim.api.nvim_get_current_buf(),
    outmode = "normal", -- depends on tag. to be updated
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

M.prep_run_block = function(task)
  local code_blocks = ts.find_all_verbatim_blocks("code", true)
  local node = code_blocks[task.blocknum]
  if not M.init_task(task) then
    return
  end
  local node_info = ts.node_info(node)
  if not node or not node_info then
    vim.notify(string.format("This is not a code block. %d", task.blocknum), "warn", { title = title })
  elseif node_info.name == "code" then
    -- default is 'normal'
    task.state.outmode = "normal"
    task.state.block_name = nil
    task.state.session = nil

    local tags = ts.node_carryover_tags(node)
    for tag, params in pairs(tags) do
      local paramS = table.concat(params)
      if tag == "exec.session" then
        task.state.session = paramS
      elseif tag == "exec.name" then
        task.state.block_name = paramS
        -- vim.notify(params)
      elseif tag == "exec.render" then
        -- vim.notify(string.format("result rendering is %s", paramS))
        if paramS == "virtual" then
          task.state.outmode = "virtual"
        end
      end
    end
    if task.state.block_name then
      vim.notify(string.format("running code block '%s'", task.state.block_name), "info", { title = title })
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
    task.state.lang_cfg = task.mconfig.lang_cmds[task.state.ft]
    if not task.state.lang_cfg then
      vim.notify("Language not supported currently!", "error", { title = title })
      return
    end
    return true
  elseif node_info.name == "result" then
    vim.notify(
    "This is a result block, not a code block. Look up to the code block!",
    "warn",
    { title = title }
    )
  else
    vim.notify(string.format("This is not a code block. %s", node_info.name), "warn", { title = title })
  end
end

return M
