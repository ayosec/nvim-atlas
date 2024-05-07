local M = {}

local FIFOStdinMark = require("atlas.searchprogram").FIFOStdinMark

local LAST_PIPELINE_ID = vim.loop.now()

---@enum atlas.searchprogram.PipelineRole
M.PipelineRole = {
    Match = "M",
    Exclude = "E",
}

---@class atlas.searchprogram.Pipeline
---@field id integer
---@field role nil|atlas.searchprogram.PipelineRole
---@field active integer
---@field process_handles table<integer, uv_process_t>
---@field stdin nil|uv_pipe_t
---@field stdout uv_pipe_t

---@class atlas.searchprogram.Pipeline
local Pipeline = {}

--- Kill active processes in the pipeline.
function Pipeline:interrupt()
    for _, handle in pairs(self.process_handles) do
        handle:kill("sigterm")
    end

    if self.stdin and not self.stdin:is_closing() then
        self.stdin:close()
    end

    if not self.stdout:is_closing() then
        self.stdout:close()
    end
end

---@alias atlas.searchprogram.Command string[][]

---@class atlas.searchprogram.RunPipelineArgs
---@field role nil|atlas.searchprogram.PipelineRole
---@field workdir? string
---@field commands atlas.searchprogram.Command
---@field stderr? atlas.searchprogram.StderrCollector
---@field open_stdin? boolean
---@field on_exit fun(pl: atlas.searchprogram.Pipeline, pid: integer, success: boolean)
---@field on_data fun(pl: atlas.searchprogram.Pipeline, data: string)

---@param run atlas.searchprogram.Pipeline
---@param args atlas.searchprogram.RunPipelineArgs
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
---@param args atlas.searchprogram.RunPipelineArgs
---@return atlas.searchprogram.Pipeline
function M.run(args)
    local main_stdout = vim.loop.new_pipe()
    assert(main_stdout)

    LAST_PIPELINE_ID = LAST_PIPELINE_ID + 1

    ---@type atlas.searchprogram.Pipeline
    local run = {
        id = LAST_PIPELINE_ID,
        role = args.role,
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

    -- If the first command is FIFOStdinMark, delete it from the list
    -- and open the linked FIFO. The path will be removed when the process
    -- is finished.
    local stdin_fifo_path = nil
    if #args.commands > 0 and args.commands[1][1] == FIFOStdinMark then
        stdin_fifo_path = args.commands[1][2]
        table.remove(args.commands, 1)
        last_pipe_fd = vim.loop.fs_open(stdin_fifo_path, "r", 0)
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

            if stdin_fifo_path then
                vim.loop.fs_unlink(stdin_fifo_path, function() end)
                stdin_fifo_path = nil
            end
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

    return setmetatable(run, { __index = Pipeline })
end

return M
