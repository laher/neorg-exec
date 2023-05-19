---@diagnostic disable: undefined-global
require("neorg.modules.base")
local ts = require("neorg.modules.external.exec.ts")
local spinner = require("neorg.modules.external.exec.spinner")
local scheduler = require("neorg.modules.external.exec.scheduler")
local renderers = require("neorg.modules.external.exec.renderers")

local title = "external.exec"
local module = neorg.modules.create("external.exec")
-- local Job = require'plenary.job'
module.setup = function()
  if vim.fn.isdirectory(module.private.tmpdir) == 0 then
    vim.fn.mkdir(module.private.tmpdir, "p")
  end
  return { success = true, requires = { "core.neorgcmd", "core.integrations.treesitter" } }
end

module.load = function()
  scheduler.start()
  ts.ts = module.required["core.integrations.treesitter"]
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

module.private = {
  task = {
    id = nil,
    running = false,
  },
  tmpdir = "/tmp/neorg-exec/", -- TODO use io.tmpname? for portability


    -- prep a task - just to put it onto the queue
    init_task = function(task)
      -- create an extmark and use its ID as an identifier
      local id = vim.api.nvim_buf_set_extmark(0, renderers.ns, 0, 0, {})

      table.insert(renderers.extmarks, id)

      task.state = {
        id = id,
        buf = vim.api.nvim_get_current_buf(),
        outmode = 'normal', -- depends on tag. to be updated
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
    end,

    handle_lines = function(task, data, hl)
      if task.state.interrupted then
        vim.fn.jobstop(task.state.jobid)
        return
      end
      renderers[task.state.outmode].append(task, data, hl)

      if task.handle_lines_extra then
        task.handle_lines_extra()
      end
    end,

    spawn = function(task, command, done)
      renderers[task.state.outmode].init(task)

      task.state.running = true
      task.state.start = os.clock()

      -- TODO: move to plenary-job?

      task.state.jobid = vim.fn.jobstart(command, {
        stdout_buffered = false,

        -- TODO: check colors
        on_stdout = function(_, data)
          module.private.handle_lines(task, data, "Function")
        end,

        on_stderr = function(_, data)
          module.private.handle_lines(task, data, "Error")
        end,

        on_exit = function(_, data)
          if data == 0 then
            vim.notify("exit - success", "info", {title = title})
          else
            vim.notify(string.format("exit - non-zero result! %d", data), "warn", {title = title})
          end

          renderers[task.state.outmode].render_exit(task, data)
          spinner.shut(task.state.spinner, renderers.ns)
          if task.state.temp_filename then
            vim.fn.delete(task.state.temp_filename)
          end
          task.state.running = false

          done()
        end,
      })
    end,

    prep_run_block = function(task)
      local code_blocks = ts.find_all_verbatim_blocks("code", true)
      local node = code_blocks[task.blocknum]
      if not module.private.init_task(task) then
        return
      end
      local node_info = ts.node_info(node)
      if node_info.name == "code" then
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
          vim.notify(string.format("running code block '%s'", task.state.block_name), "info", {title = title})
        else
          vim.notify("running unnamed code block", "info", {title = title})
        end
        task.state["node"] = node
        task.state["code_block"] = node_info

        -- FIX: temp fix remove this!
        -- Amir: I wonder what this fix was for
        node_info["parameters"] = vim.split(node_info["parameters"][1], " ")
        local ft = node_info.parameters[1]
        task.state["ft"] = ft
        task.state.lang_cfg = module.config.public.lang_cmds[task.state.ft]
        if not task.state.lang_cfg then
          vim.notify("Language not supported currently!", "error", {title = title})
          return
        end
        return true
      elseif node_info.name == "result" then
        vim.notify("This is a result block, not a code block. Look up to the code block!", "warn", {title = title})
      else
        vim.notify(string.format("This is not a code block. %s", node_info.name), "warn", {title = title})
      end
    end,

    init_session = function(task, tx)
      local command = task.state.lang_cfg.repl
      module.private.spawn(task, command, tx)
    end,

    do_run_block_session = function(task)
      -- initialize block
      renderers[task.state.outmode].init(task)

      local content = table.concat(task.state.code_block.content, "\n")
      vim.notify(string.format("send to running session: %s", content), "info", {title = title})
      vim.api.nvim_chan_send(task.state.jobid, content)

      -- after receiving response (hopefully the whole response)
      task.handle_lines_extra = function()
        renderers[task.state.outmode].render_exit(task, nil)
        spinner.shut(task.state.spinner, renderers.ns)
        task.handle_lines_extra = nil
      end
    end,

    do_run_block_spawn = function(task, tx)
      -- TODO - use io.tmpfile() / io.tmpname()?
      -- create a temp file and run it
      task.state.temp_filename = module.private.tmpdir .. task.state.id .. "." .. task.state.ft
      local file = io.open(task.state.temp_filename, "w")
      -- TODO: better error.
      if file == nil then
        return
      end

      local file_content = table.concat(task.state.code_block.content, "\n")
      if not vim.tbl_contains(task.state.code_block.parameters, ":main") and task.state.lang_cfg.type == "compiled" then
        local c = task.state.lang_cfg.main_wrap
        file_content = c:gsub("${1}", file_content)
      end
      file:write(file_content)
      file:close()

      local command = task.state.lang_cfg.cmd:gsub("${0}", task.state.temp_filename)
      module.private.spawn(task, command, tx)
    end,


  }

module.public = {
  -- TODO - all blocks in a section
  do_code_block_under_cursor = function()
    local my_block = ts.current_verbatim_tag()
    if my_block then
      -- NOTE the block will be reevaluated in treesitter by the scheduler, because each result updates the AST
      -- It needs to calculate which block it is,
      -- in case another block is already running & the line number may change
      local code_blocks = ts.find_all_verbatim_blocks("code", true)
      for i, doc_block in ipairs(code_blocks) do
        if my_block == doc_block then
          scheduler.enqueue({
            task_type = 'run_block',
            blocknum = i,
            prep = module.private.prep_run_block,
            -- don't know which strategy yet
            do_task_spawn = module.private.do_run_block_spawn,
            init_session = module.private.init_session,
            do_task_session = module.private.do_run_block_session,
            state = nil,
          })
        end
      end
    else
      local my_blocks = ts.contained_verbatim_blocks("code", true)
      if not my_blocks or #my_blocks == 0 then
        vim.notify(string.format("This is not a code block (or a heading containing code blocks)"), "warn", {title = title})
      end
      for i, _ in ipairs(my_blocks) do
        -- vim.notify('found a match inside current block')
        scheduler.enqueue({
          task_type = 'run_block',
          blocknum = i,
          prep = module.private.prep_run_block,
            -- don't know which strategy yet
          do_task = module.private.do_run_block_spawn,
          init_session = module.private.init_session,
          do_task_session = module.private.do_run_block_session,
          state = nil,
        })
      end
    end
  end,

  do_buf = function()
    local code_blocks = ts.find_all_verbatim_blocks("code", true)
    for i, _ in ipairs(code_blocks) do
      -- We really just need the index of each block within the scope.
      -- After a block completes, the next block needs to be found all over again
      scheduler.enqueue({
        task_type = 'run_block',
        blocknum = i,
        prep = module.private.prep_run_block,
          -- don't know which strategy yet
        do_task = module.private.do_run_block_spawn,
        init_session = module.private.init_session,
        do_task_session = module.private.do_run_block_session,
        state = nil,
        })
      end
    end,


    -- find *all* virtmarks and delete them
    hide = function()
      -- TODO put this on the queue?
      vim.api.nvim_buf_clear_namespace(0, renderers.ns, 0, -1)
      local result_blocks = ts.find_all_verbatim_blocks("result")
      vim.notify(string.format('found %d', #result_blocks), 'info', {title = title})

      -- iterate backwards to avoid needing to recalculate positions
      for i = #result_blocks, 1, -1 do
        local block = result_blocks[i]
        local start_row = ts.node_carryover_tags_firstline(block)
        local end_row,_,_ = block:end_()
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

    -- TODO: find *all* virtmarks and materialize them. Track them separately to tasks
    materialize = function()
      local marks = vim.api.nvim_buf_get_extmarks(0, renderers.ns, 0, -1, {})
      for _, mark in ipairs(marks) do
        -- mark is [id,row,col]
        local out = {}
        local curr_task = renderers.extmarks[mark[1]]

        vim.notify(string.format('found %s - %d',mark[1], #curr_task.output))
        if curr_task then
          for _, line in ipairs(curr_task.output) do
            table.insert(out, line[1][1])
            --vim.notify(string.format('line %s', line[1][1]))
            --return
          end
          vim.notify(string.format('out: %s - %s',mark[2], #out))
          vim.api.nvim_buf_set_lines(
          curr_task.buf,
          mark[2]+1,
          mark[2]+1,
          true,
          out
          )
        end
        vim.api.nvim_buf_del_extmark(0, renderers.ns, mark[1])
        renderers.extmarks = {} -- clear it out
      end
      return

      -- local cr, _ = unpack(vim.api.nvim_win_get_cursor(0))

      -- if module.private.task.id then
      --   local curr_task = module.private.task
      --   local code_start = curr_task.code_block["start"].row + 1
      --   local code_end = curr_task.code_block["end"].row + 1
      --
      --   if code_start <= cr and code_end >= cr then
      --     -- clear virtual lines
      --     vim.api.nvim_buf_set_extmark(
      --     curr_task.buf,
      --     renderers.ns,
      --     curr_task.code_block["end"].row,
      --     0,
      --     { id = curr_task.id, virt_lines = nil }
      --     )
      --     module.private.clear_next_result_tag(curr_task.buf, curr_task.node)
      --
      --     local t = vim.tbl_map(function(line)
        --       return line[1][1]
        --     end, curr_task.output)
        --
        --     vim.api.nvim_buf_set_lines(
        --     curr_task.buf,
        --     curr_task.code_block["end"].row+1,
        --     curr_task.code_block["end"].row+1,
        --     true,
        --     t
        --     )
        --
        --     module.private.mode = "normal"
        --     module.private.task = { running = false }
        --   end
        -- end
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
