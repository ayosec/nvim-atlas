local PipeOutput = require("atlas.pipeline").PipeOutput

local buffer = require("string.buffer")

local M = {}

---@class atlas.pipeline.Result
---@field file string
---@field line? integer
---@field text? string

---@class atlas.impl.StderrCollector
---@field fd_write integer
---@field handle_reader any
---@field buffer string.buffer

---@class atlas.pipeline.RunningContext
---@field running integer
---@field failed boolean
---@field stderr atlas.impl.StderrCollector
---@field process_handles table<integer, any>
---@field pipeline_output string.buffer
---@field output_kind atlas.pipeline.PipeOutput
---@field on_success fun(results: atlas.pipeline.Result[])
---@field on_error fun(stderr: string)

---@return atlas.impl.StderrCollector
local function stderr_collector()
    local pipes = vim.loop.pipe()
    local output = buffer.new()

    local wrapper = vim.loop.new_pipe()

    local function reader(err, data)
        if err then
            output:putf("stderr reader failed: %s\n", vim.inspect(err))
        end

        if data then
            output:put(data)
        else
            wrapper:close()
        end
    end

    wrapper:open(pipes.read)
    wrapper:read_start(reader)

    return {
        fd_write = pipes.write,
        handle_reader = wrapper,
        buffer = output,
    }
end

---@param context atlas.pipeline.RunningContext
---@return atlas.pipeline.Result[]
local function build_results(context)
    local results = {}

    local output = context.pipeline_output:tostring()
    context.pipeline_output:free()

    if context.output_kind == PipeOutput.JsonLines then
        for line in vim.gsplit(output, "\n", { trimempty = true }) do
            local item = vim.json.decode(line)
            if item.type == "match" then
                table.insert(results, {
                    file = item.data.path.text,
                    line = item.data.line_number,
                    text = item.data.lines.text:gsub("\n$", ""),
                })
            end
        end
    end

    if context.output_kind == PipeOutput.FileNames then
        for filename in vim.gsplit(output, "\0", { trimempty = true }) do
            table.insert(results, { file = filename })
        end
    end

    return results
end

---@param context atlas.pipeline.RunningContext
---@param pid integer
---@param success boolean
local function on_exit_handler(context, pid, success)
    local handle = context.process_handles[pid]
    if handle then
        handle:close()
    end

    context.running = context.running - 1

    if not success then
        context.failed = true
    end

    -- Check if the pipeline is done.
    if context.running > 0 then
        return
    end

    if context.failed then
        context.on_error(context.stderr.buffer:tostring())
        return
    end

    -- Process the output from the pipeline.
    context.on_success(build_results(context))
end

--- Execute the commands in the pipeline, and invoke the
--- handlers when they are finished.
---
---@param config atlas.Config
---@param pipeline atlas.pipeline.Pipeline
---@param on_success fun(results: atlas.pipeline.Result[])
---@param on_error fun(stderr: string)
function M.run(config, pipeline, on_success, on_error)
    local search_dir = config.files.search_dir()

    local stderr = stderr_collector()

    local context = {
        running = 0,
        failed = false,
        stderr = stderr,
        process_handles = {},
        pipeline_output = buffer.new(),
        output_kind = pipeline.output_kind,
        on_error = on_error,
        on_success = on_success,
    }

    local last_pipe_fd = nil

    for _, command in ipairs(pipeline.commands) do
        local stdio_pipe = vim.loop.pipe()

        local spawn_args = {
            args = vim.list_slice(command, 2),
            hide = true,
            stdio = {
                last_pipe_fd,
                stdio_pipe.write,
                stderr.fd_write,
            },
        }

        if search_dir ~= nil then
            spawn_args.cwd = search_dir
        end

        local handle, pid
        handle, pid = vim.loop.spawn(command[1], spawn_args, function(code, signal)
            on_exit_handler(context, pid, code == 0 and signal == 0)
        end)

        context.running = context.running + 1
        context.process_handles[pid] = handle

        if last_pipe_fd ~= nil then
            vim.loop.fs_close(last_pipe_fd)
        end

        last_pipe_fd = stdio_pipe.read

        vim.loop.fs_close(stdio_pipe.write)
    end

    vim.loop.fs_close(stderr.fd_write)

    -- Collect data from the last process of the pipeline.
    local stdout_wrapper = vim.loop.new_pipe()
    stdout_wrapper:open(last_pipe_fd)
    stdout_wrapper:read_start(function(err, data)
        if err then
            context.failed = true
            context.stderr.buffer:putf("stdout reader failed: %s\n", vim.inspect(err))
        end

        if data then
            context.pipeline_output:put(data)
        else
            stdout_wrapper:close()
        end
    end)
end

return M
