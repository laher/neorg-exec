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
local choose_worker = function(rt_info)
  return nil
end

local do_task = function(task)

  -- session_identifier is only set when it's a session id
  -- the task needs to recalculate where the hell the block is now (maybe location has changed)
  -- and then defines runtime info for execution
  -- local rt_info = task.prep()
  -- local worker = choose_worker(rt_info)
  -- if worker then
  --   worker.execute(task, rt_info)
  -- end
  -- vim.notify('recieved task yay')
  -- oops for now it's super dumb

--  local a = require'plenary.async'
  local tx, rx = a.control.channel.oneshot()
  task.do_task(task, tx)
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
        vim.notify('task complete. next')
      end
    end)
end




return M
