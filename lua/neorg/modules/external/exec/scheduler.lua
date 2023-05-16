local M = {
  active = false,
  sessions = {},
  find_code_block = nil,
  choose_worker = nil,
  execute = nil,
}

-- set up a private pub/sub queue
local a = require'plenary.async'
-- multi-producer single consumer
local sender, receiver = a.control.channel.mpsc()


M.enqueue = function(task)
  a.run(function()
    sender.send(task)
  end)
end

M.stop = function()
  M.active = false
end

-- initially just creaet a new one each time
-- TODO match runtime info to workers when there's a session
local find_session = function(task)
  -- if session then repl
  -- otherwise new process
  return nil
end

local do_task = function(task)

  -- TODO when doing sessions
  -- session_identifier is only set when it's a session id
  -- the task needs to recalculate where the hell the block is now (maybe location has changed)
  -- and then defines runtime info for execution
  if not task.prep(task) then
    return function()
      -- nothing to do
    end
  end


  local session = find_session(task)
  local tx, rx = a.control.channel.oneshot()
  if session then
    task.do_task_session(task, tx, session)
  else
    task.do_task_spawn(task, tx)
  end
  return rx
end

M.start = function()
  if M.active then
    vim.notify('called start again?!')
    return
  end
    M.active = true
    a.run(function()
      -- ooh running on its own thread
      while M.active do
        local task = receiver.recv()
        -- print('received:', task)
        local done = do_task(task)
        done() -- block
        -- vim.notify('task complete. next')
      end
    end)
end




return M
