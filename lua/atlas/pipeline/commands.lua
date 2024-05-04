local M = {}

---@class atlas.pipeline.RunningCommands
---@field active integer
---@field process_handles table<integer, uv_process_t>
---@field stdin? uv_pipe_t
---@field stdout uv_pipe_t

---@class atlas.pipeline.RunningCommands
local RunningCommands = {}

--- Kill active processes in the pipeline.
function RunningCommands:interrupt()
    for _, handle in pairs(self.process_handles) do
        handle:kill("sigterm")
    end
end

---@class atlas.pipeline.RunningCommandsArgs
---@field workdir? string
---@field commands string[][]
---@field stderr? atlas.pipeline.StderrCollector
---@field open_stdin? boolean
---@field on_exit fun(rc: atlas.pipeline.RunningCommands, pid: integer, success: boolean)
---@field on_data fun(rc: atlas.pipeline.RunningCommands, data: string)

---@param run atlas.pipeline.RunningCommands
---@param args atlas.pipeline.RunningCommandsArgs
---@param pid integer
---@param success boolean
local function handle_exit(run, args, pid, success)
    local handle = run.process_handles[pid]
    if handle then
        handle:close()
        run.process_handles[pid] = nil
    end

    run.active = run.active - 1

    args.on_exit(run, pid, success)
end

--- Run the commands for a new pipeline.
---
---@param args atlas.pipeline.RunningCommandsArgs
---@return atlas.pipeline.RunningCommands
function M.run(args)
    local main_stdout = vim.loop.new_pipe()
    assert(main_stdout)

    ---@type atlas.pipeline.RunningCommands
    local run = {
        active = 0,
        process_handles = {},
        stdout = main_stdout,
    }

    local stderr_fd = args.stderr and args.stderr.fd_write
    local last_pipe_fd = nil

    if args.open_stdin then
        local fds = vim.loop.pipe()
        assert(fds)

        last_pipe_fd = fds.read

        local pipe = vim.loop.new_pipe()
        assert(pipe)
        pipe:open(fds.write)
        run.stdin = pipe
    end

    -- Run commands.

    for _, command in ipairs(args.commands) do
        local stdio_pipe = vim.loop.pipe()
        assert(stdio_pipe)

        local spawn_args = {
            args = vim.list_slice(command, 2),
            hide = true,
            cwd = args.workdir,
            stdio = {
                last_pipe_fd,
                stdio_pipe.write,
                stderr_fd,
            },
        }

        local handle, pid
        handle, pid = vim.loop.spawn(command[1], spawn_args, function(code, signal)
            handle_exit(run, args, pid, code == 0 and signal == 0)
        end)

        run.active = run.active + 1
        run.process_handles[pid] = handle

        if last_pipe_fd ~= nil then
            vim.loop.fs_close(last_pipe_fd)
        end

        last_pipe_fd = stdio_pipe.read

        vim.loop.fs_close(stdio_pipe.write)
    end

    -- Collect data from the last process of the pipeline.
    main_stdout:open(last_pipe_fd)
    main_stdout:read_start(function(err, data)
        if err and args.stderr then
            args.stderr.buffer:putf("stdout reader failed: %s\n", vim.inspect(err))
        end

        if not data then
            main_stdout:close()
            return
        end

        args.on_data(run, data)
    end)

    return setmetatable(run, { __index = RunningCommands })
end

return M
