local PipeOutput = require("atlas.pipeline").PipeOutput
local Commands = require("atlas.pipeline.commands")
local Stderr = require("atlas.pipeline.stderr")

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

---@class atlas.pipeline.RunningContext
---@field search_dir string
---@field max_results integer
---@field running integer
---@field reader_status atlas.pipeline.ReaderStatus
---@field stderr atlas.pipeline.StderrCollector
---@field command_pipelines atlas.pipeline.RunningCommands[]
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
    for _, cp in pairs(self.command_pipelines) do
        cp:interrupt()
    end
end

---@param context atlas.pipeline.RunningContext
---@param data string
local function results_collector(context, data)
    data = context.pipeline_output_pending .. data
    context.pipeline_output_pending = context.pipeline_output_parser(context, data)

    if #context.pipeline_result.items >= context.max_results then
        -- Truncate list. Items after `max_results` are still in the table,
        -- but they will not be visible by `ipairs`
        context.pipeline_result.items[context.max_results + 1] = nil

        context:set_reader_status(ReaderStatus.Complete)
    end
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
---@param success boolean
local function on_exit_handler(context, success)
    if not success then
        context:set_reader_status(ReaderStatus.Failed)
    end

    -- Check if the pipeline is done.
    if context.command_pipelines[1].active > 0 then
        return
    end

    if context.reader_status == ReaderStatus.Failed then
        context.on_error(context.stderr:get())
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

    local stderr = Stderr.collector()

    local context = {
        search_dir = search_dir,
        max_results = config.search.max_results,
        running = 0,
        reader_status = ReaderStatus.Reading,
        stderr = stderr,
        command_pipelines = {},
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

    context.command_pipelines[1] = Commands.run {
        workdir = search_dir,
        commands = pipeline.commands,
        stderr = stderr,

        on_exit = function(_, _, success)
            on_exit_handler(context, success)
        end,

        on_data = function(_, data)
            results_collector(context, data)
        end,
    }

    stderr:close_write()

    return context
end

return M
