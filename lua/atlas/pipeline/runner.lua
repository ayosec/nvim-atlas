local PipeOutput = require("atlas.pipeline").PipeOutput

local buffer = require("string.buffer")

local M = {}

---@class atlas.pipeline.Result
---@field items atlas.pipeline.ResultItem[]
---@field max_line_number integer

---@class atlas.pipeline.ResultItem
---@field file string
---@field line? integer
---@field text? string

---@class atlas.impl.StderrCollector
---@field fd_write integer
---@field handle_reader any
---@field buffer string.buffer

---@class atlas.pipeline.RunningContext
---@field max_results integer
---@field found_results integer
---@field running integer
---@field reader_status atlas.pipeline.ReaderStatus
---@field stderr atlas.impl.StderrCollector
---@field process_handles table<integer, any>
---@field pipeline_output string.buffer
---@field output_kind atlas.pipeline.PipeOutput
---@field on_success fun(results: atlas.pipeline.Result)
---@field on_error fun(stderr: string)

---@enum atlas.pipeline.ReaderStatus
local ReaderStatus = {
    Reading = 1,
    Complete = 2,
    Notified = 3,
    Failed = 4,
}

---@class atlas.pipeline.RunningContext
local RunningContext = {}

---@param status atlas.pipeline.ReaderStatus
function RunningContext:set_reader_status(status)
    if self.reader_status == ReaderStatus.Reading then
        self.reader_status = status
    end
end

function RunningContext:interrupt()
    for _, handle in pairs(self.process_handles) do
        handle:kill()
    end
end

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
---@param pipe_fd any
local function results_collector(context, pipe_fd)
    local entry_sep = context.output_kind == PipeOutput.JsonLines and "\n" or "\0"

    local wrap = vim.loop.new_pipe()
    wrap:open(pipe_fd)
    wrap:read_start(function(err, data)
        if err then
            context:set_reader_status(ReaderStatus.Failed)
            context.stderr.buffer:putf("stdout reader failed: %s\n", vim.inspect(err))
        end

        if not data then
            wrap:close()
            return
        end

        -- Count how many entries have been read from the pipeline, and close
        -- the pipe if we have reached the maximum.
        local offset = 1
        while context.found_results < context.max_results do
            -- TODO In JsonLines, ignore events where `type ≠ match`
            local o = data:find(entry_sep, offset, { plain = true })
            if o then
                context.found_results = context.found_results + 1
                offset = o + 1
            else
                break
            end
        end

        if context.found_results == context.max_results then
            -- Discard entries after the last separator.
            if offset > 1 then
                context.pipeline_output:put(data:sub(1, offset - 1))
            end

            context:set_reader_status(ReaderStatus.Complete)
            wrap:close()
        else
            context.pipeline_output:put(data)
        end
    end)
end

---@param context atlas.pipeline.RunningContext
---@return atlas.pipeline.Result
local function build_results(context)
    local items = {}
    local max_line_number = 0

    local max_results = context.max_results

    local output = context.pipeline_output:tostring()
    context.pipeline_output:free()

    if context.output_kind == PipeOutput.JsonLines then
        for line in vim.gsplit(output, "\n", { trimempty = true }) do
            local item = vim.json.decode(line)
            if item.type == "match" then
                local line_number = item.data.line_number
                table.insert(items, {
                    file = item.data.path.text,
                    line = line_number,
                    text = item.data.lines.text:gsub("\n$", ""),
                })

                if line_number ~= nil and line_number > max_line_number then
                    max_line_number = line_number
                end

                if #items >= max_results then
                    break
                end
            end
        end
    end

    if context.output_kind == PipeOutput.FileNames then
        for filename in vim.gsplit(output, "\0", { trimempty = true }) do
            table.insert(items, { file = filename })

            if #items >= max_results then
                break
            end
        end
    end

    return {
        items = items,
        max_line_number = max_line_number,
    }
end

---@param context atlas.pipeline.RunningContext
---@param pid integer
---@param success boolean
local function on_exit_handler(context, pid, success)
    local handle = context.process_handles[pid]
    if handle then
        handle:close()
        context.process_handles[pid] = nil
    end

    context.running = context.running - 1

    if not success then
        context:set_reader_status(ReaderStatus.Failed)
    end

    -- Check if the pipeline is done.
    if context.running > 0 then
        return
    end

    if context.reader_status == ReaderStatus.Failed then
        context.on_error(context.stderr.buffer:tostring())
        return
    end

    -- Process the output from the pipeline.
    if context.reader_status ~= ReaderStatus.Notified then
        context.reader_status = ReaderStatus.Notified
        context.on_success(build_results(context))
    end
end

--- Execute the commands in the pipeline, and invoke the
--- handlers when they are finished.
---
---@param config atlas.Config
---@param pipeline atlas.pipeline.Pipeline
---@param on_success fun(result: atlas.pipeline.Result)
---@param on_error fun(stderr: string)
---@return atlas.pipeline.RunningContext
function M.run(config, pipeline, on_success, on_error)
    local search_dir = config.files.search_dir()

    local stderr = stderr_collector()

    local context = {
        max_results = config.search.max_results,
        found_results = 0,
        running = 0,
        reader_status = ReaderStatus.Reading,
        stderr = stderr,
        process_handles = {},
        pipeline_output = buffer.new(),
        output_kind = pipeline.output_kind,
        on_error = on_error,
        on_success = on_success,
    }

    context = setmetatable(context, { __index = RunningContext })

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
    results_collector(context, last_pipe_fd)

    return context
end

return M
