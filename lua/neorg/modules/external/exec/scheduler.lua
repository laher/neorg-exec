local M = {
    active = false,
    sessions = {},
    find_code_block = nil,
    choose_worker = nil,
    execute = nil,
}

local title = "external.exec.scheduler"

-- set up a private pub/sub queue
local a = require("plenary.async")
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
local find_or_init_session = function(task)
    -- if session then repl
    if task.state.session and task.state.session ~= "" and task.state.lang_cfg.repl then
        local key = task.state.ft .. ":" .. task.state.session
        if M.sessions[key] then
            local s = M.sessions[key]

            if s.state.running then
                vim.notify("found running repl. Send to repl", "info", { title = title })
                -- update all state except keep jobid
                task.state.jobid = s.state.jobid
                task.state.running = s.state.running
                s.state = task.state
                return s
            end
            vim.notify("process is gone. restart session", "warn", { title = title })
            -- it's dead, Jim. start another session
        end
        -- create session
        task.init_session(task, function() end)
        M.sessions[key] = task
        return task
    end
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
            -- nothing to rx
        end
    end
    local session = find_or_init_session(task)
    if session then
        session.do_task_session(session)
        return function() end
    else
        local tx, rx = a.control.channel.oneshot()
        task.do_task_spawn(task, tx)
        return rx
    end
end

M.start = function()
    if M.active then
        vim.notify("called start again?!", "warn", { title = title })
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
