local PipeOutput = require("atlas.pipeline").PipeOutput

local buffer = require("string.buffer")

local M = {}

---@class atlas.pipeline.Result
---@field search_dir string
---@field items atlas.pipeline.ResultItem[]
---@field max_line_number integer

---@class atlas.pipeline.ResultItem
---@field file string
---@field line? integer
---@field text? string
---@field highlights? integer[][]

---@class atlas.impl.StderrCollector
---@field fd_write integer
---@field handle_reader uv_pipe_t
---@field buffer string.buffer

---@class atlas.pipeline.RunningContext
---@field search_dir string
---@field max_results integer
---@field running integer
---@field reader_status atlas.pipeline.ReaderStatus
---@field stderr atlas.impl.StderrCollector
---@field process_handles table<integer, uv_process_t>
---@field pipeline_output_pending string
---@field pipeline_output_parser fun(context: atlas.pipeline.RunningContext, data: string):string
---@field pipeline_result atlas.pipeline.Result
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
        handle:kill("sigterm")
    end
end

---@return atlas.impl.StderrCollector
local function stderr_collector()
    local pipes = vim.loop.pipe()
    assert(pipes)

    local output = buffer.new()

    local wrapper = vim.loop.new_pipe()
    assert(wrapper)

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
    local wrap = vim.loop.new_pipe()
    assert(wrap)

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

        data = context.pipeline_output_pending .. data
        context.pipeline_output_pending = context.pipeline_output_parser(context, data)

        if #context.pipeline_result.items >= context.max_results then
            -- Truncate list. Items after `max_results` are still in the table,
            -- but they will not be visible by `ipairs`
            context.pipeline_result.items[context.max_results + 1] = nil

            context:set_reader_status(ReaderStatus.Complete)
            wrap:close()
        end
    end)
end

---@param context atlas.pipeline.RunningContext
---@param data string
---@return string
local function pipeline_output_parse_json_lines(context, data)
    local result = context.pipeline_result
    local offset = 1

    while true do
        local sep = data:find("\n", offset, true)
        if sep == nil then
            return data:sub(offset)
        end

        local line = data:sub(offset, sep - 1)
        offset = sep + 1

        local item = vim.json.decode(line)
        if item.type == "match" then
            local highlights = nil
            local line_number = item.data.line_number
            local text = item.data.lines.text

            if text then
                text = text:gsub("\n$", "")
            end

            local submatches = item.data.submatches
            if submatches ~= nil then
                highlights = {}
                for _, submatch in ipairs(submatches) do
                    table.insert(highlights, { submatch.start, submatch["end"] })
                end
            end

            table.insert(result.items, {
                file = item.data.path.text,
                line = line_number,
                text = text,
                highlights = highlights,
            })

            if line_number ~= nil and line_number > result.max_line_number then
                result.max_line_number = line_number
            end
        end
    end
end

---@param context atlas.pipeline.RunningContext
---@param data string
---@return string
local function pipeline_output_parse_filenames(context, data)
    local result = context.pipeline_result
    local offset = 1

    while true do
        local sep = data:find("\0", offset, true)
        if sep == nil then
            return data:sub(offset)
        end

        local filename = data:sub(offset, sep - 1)
        table.insert(result.items, { file = filename })

        offset = sep + 1
    end
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
        context.on_success(context.pipeline_result)
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
    ---@type string
    local search_dir = vim.fn.fnamemodify(config.files.search_dir() or ".", ":p")

    local stderr = stderr_collector()

    local context = {
        search_dir = search_dir,
        max_results = config.search.max_results,
        running = 0,
        reader_status = ReaderStatus.Reading,
        stderr = stderr,
        process_handles = {},
        pipeline_output_pending = "",
        pipeline_result = {
            search_dir = search_dir,
            items = {},
            max_line_number = 0,
        },
        on_error = on_error,
        on_success = on_success,
    }

    if pipeline.output_kind == PipeOutput.FileNames then
        context.pipeline_output_parser = pipeline_output_parse_filenames
    else
        context.pipeline_output_parser = pipeline_output_parse_json_lines
    end

    context = setmetatable(context, { __index = RunningContext })

    local last_pipe_fd = nil

    for _, command in ipairs(pipeline.commands) do
        local stdio_pipe = vim.loop.pipe()
        assert(stdio_pipe)

        local spawn_args = {
            args = vim.list_slice(command, 2),
            hide = true,
            cwd = search_dir,
            stdio = {
                last_pipe_fd,
                stdio_pipe.write,
                stderr.fd_write,
            },
        }

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
