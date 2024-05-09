local OutputKind = require("atlas.searchprogram").OutputKind
local Pipeline = require("atlas.searchprogram.pipeline")
local Stderr = require("atlas.searchprogram.stderr")

local M = {}

---@class atlas.searchprogram.ProgramOutput
---@field search_dir string
---@field items atlas.searchprogram.ResultItem[]
---@field max_line_number integer

---@class atlas.searchprogram.ResultItem
---@field file string
---@field line? integer
---@field text? string
---@field highlights? integer[][]
---@field main_highlight_group? string

---@class atlas.searchprogram.ContentMatch
---@field item atlas.searchprogram.ResultItem
---@field match_pipelines table<integer, boolean>
---@field exclude boolean|nil

---@class atlas.searchprogram.RunningContext
---@field program atlas.searchprogram.Program
---@field search_dir string
---@field max_results integer
---@field running integer
---@field reader_status atlas.searchprogram.ReaderStatus
---@field stderr atlas.searchprogram.StderrCollector
---@field command_pipelines atlas.searchprogram.Pipeline[]
---@field output_pipeline_ids integer[]
---@field pipeline_output_pending table<integer, string>
---@field pipeline_output_parser fun(context: atlas.searchprogram.RunningContext, pipeline: atlas.searchprogram.Pipeline, data: string): string
---@field program_output atlas.searchprogram.ProgramOutput
---@field content_matches table<string, atlas.searchprogram.ContentMatch>
---@field content_exclude_line_keys string[]
---@field content_exclude_pipe uv_pipe_t|nil
---@field on_success fun(results: atlas.searchprogram.ProgramOutput)
---@field on_error fun(stderr: string)

---@enum atlas.searchprogram.ReaderStatus
local ReaderStatus = {
    Reading = 1,
    Complete = 2,
    Notified = 3,
    Failed = 4,
}

---@class atlas.searchprogram.RunningContext
local RunningContext = {}

---@param status atlas.searchprogram.ReaderStatus
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

---@param context atlas.searchprogram.RunningContext
---@param pipeline atlas.searchprogram.Pipeline
---@param data string
local function results_collector(context, pipeline, data)
    local pending_data = context.pipeline_output_pending[pipeline.id]
    if pending_data then
        data = pending_data .. data
    end

    context.pipeline_output_pending[pipeline.id] = context.pipeline_output_parser(context, pipeline, data)

    if #context.program_output.items >= context.max_results then
        -- Truncate list. Items after `max_results` are still in the table,
        -- but they will not be visible by `ipairs`
        context.program_output.items[context.max_results + 1] = nil

        context:set_reader_status(ReaderStatus.Complete)
    end
end

---@param item atlas.searchprogram.ResultItem
---@param new_hls integer[][]
local function insert_highlight(item, new_hls)
    local highlights = item.highlights

    if not highlights then
        item.highlights = new_hls
        return
    end

    -- Check if the new highlights are overlapping with the existing ones.

    local overlapping = false
    for _, new_hl in ipairs(new_hls) do
        local start = new_hl[1]
        local end_ = new_hl[2]

        for _, hl in ipairs(highlights) do
            if hl[2] >= start and hl[1] <= end_ then
                overlapping = true
                break
            end
        end

        if overlapping then
            break
        end
    end

    vim.list_extend(highlights, new_hls)

    if not overlapping then
        return
    end

    -- The highlights list contains overlapped ranges. The process must be
    -- repeated until there are no more overlaps because new highlights can
    -- overlaps multiple ranges.
    --
    -- For example, if the range { 5, 10 } is added to { { 4, 6 }, { 8, 12 } },
    -- the final list should be just { { 4, 12 } }.

    local found_overlapped = true
    while found_overlapped do
        found_overlapped = false

        for i = 1, #highlights - 1 do
            local hl_base = highlights[i]
            if #hl_base == 2 then
                for j = i + 1, #highlights do
                    local hl = highlights[j]

                    if #hl == 2 and hl[2] >= hl_base[1] and hl[1] <= hl_base[2] then
                        highlights[i] = {
                            math.min(hl[1], hl_base[1]),
                            math.max(hl[2], hl_base[2]),
                        }

                        highlights[j] = {}
                        found_overlapped = true
                    end
                end
            end
        end
    end

    item.highlights = vim.tbl_filter(function(hl)
        return #hl == 2
    end, highlights)
end

---@param context atlas.searchprogram.RunningContext
---@param pipeline atlas.searchprogram.Pipeline
---@param data string
---@return string
local function pipeline_output_parse_json_lines(context, pipeline, data)
    local result = context.program_output
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

            ---@type atlas.searchprogram.ResultItem
            local result_item = {
                file = item.data.path.text,
                line = line_number,
                text = text,
                highlights = highlights,
            }

            local program = context.program
            if #program.output_commands == 1 and not program.exclude_command then
                -- If there is only one pipeline, the match is added directly
                -- to the program output.

                table.insert(result.items, result_item)

                if line_number ~= nil and line_number > result.max_line_number then
                    result.max_line_number = line_number
                end
            else
                -- If there are multiple pipelines, track matches in a separate
                -- table, which will be processed when all pipelines are done.

                local key = string.format("%s:%d", result_item.file, result_item.line)
                local cm = context.content_matches[key]
                if cm then
                    if not cm.exclude then
                        cm.match_pipelines[pipeline.id] = true
                        if highlights then
                            insert_highlight(cm.item, highlights)
                        end
                    end
                else
                    context.content_matches[key] = {
                        item = result_item,
                        match_pipelines = { [pipeline.id] = true },
                    }
                end

                if context.content_exclude_pipe and text then
                    table.insert(context.content_exclude_line_keys, key)
                    context.content_exclude_pipe:write { text, "\0" }
                end
            end
        end
    end
end

---@param context atlas.searchprogram.RunningContext
---@param data string
---@return string
local function pipeline_output_parse_filenames(context, _, data)
    local result = context.program_output
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

---@param context atlas.searchprogram.RunningContext
---@param pipeline atlas.searchprogram.Pipeline
---@param data string
local function process_exclude_content_filter(context, pipeline, data)
    local pending_data = context.pipeline_output_pending[pipeline.id]
    if pending_data then
        data = pending_data .. data
    end

    local offset = 1

    while true do
        local sep = data:find("\0", offset, true)
        if sep == nil then
            context.pipeline_output_pending[pipeline.id] = data:sub(offset)
            return
        end

        local colon = data:find(":", offset, true)
        if colon then
            local line = tonumber(data:sub(offset, colon - 1))
            local key = line and context.content_exclude_line_keys[line]
            local cm = key and context.content_matches[key]
            if cm and not cm.exclude then
                cm.exclude = true
                cm.item.highlights = {}
            end
        end

        offset = sep + 1
    end
end

---@param context atlas.searchprogram.RunningContext
---@return atlas.searchprogram.ProgramOutput
local function generate_program_output(context)
    local output = context.program_output
    local max_results = context.max_results

    for _, cm in pairs(context.content_matches) do
        local match_all_pipelines = false

        if not cm.exclude then
            match_all_pipelines = true
            for _, pipeline_id in ipairs(context.output_pipeline_ids) do
                if not cm.match_pipelines[pipeline_id] then
                    match_all_pipelines = false
                    break
                end
            end
        end

        if match_all_pipelines then
            table.sort(cm.item.highlights, function(a, b)
                return a[1] < b[1]
            end)

            table.insert(output.items, cm.item)

            local line = cm.item.line
            if line and line > output.max_line_number then
                output.max_line_number = line
            end

            if #output.items > max_results then
                break
            end
        end
    end

    return context.program_output
end

---@param context atlas.searchprogram.RunningContext
---@param success boolean
local function on_exit_handler(context, success)
    if not success then
        context:set_reader_status(ReaderStatus.Failed)
    end

    -- Check if all pipelines are done.
    local Exclude = Pipeline.PipelineRole.Exclude
    for _, pipeline in pairs(context.command_pipelines) do
        if pipeline.active > 0 and pipeline.role ~= Exclude then
            return
        end
    end

    -- If the exclude pipeline is still running, close its
    -- stdin and wait for its termination.
    if context.content_exclude_pipe then
        context.content_exclude_pipe:close()
        context.content_exclude_pipe = nil
        return
    end

    if context.reader_status == ReaderStatus.Failed then
        context.on_error(context.stderr:get())
        return
    end

    -- Process the output from the pipeline.
    if context.reader_status ~= ReaderStatus.Notified then
        context.reader_status = ReaderStatus.Notified
        context.on_success(generate_program_output(context))
    end
end

--- Execute the commands in the pipeline, and invoke the
--- handlers when they are finished.
---
---@param config atlas.Config
---@param program atlas.searchprogram.Program
---@param on_success fun(result: atlas.searchprogram.ProgramOutput)
---@param on_error fun(stderr: string)
---@return atlas.searchprogram.RunningContext
function M.run(config, program, on_success, on_error)
    ---@type string
    local search_dir = vim.fn.fnamemodify(program.search_dir or config.files.search_dir() or ".", ":p")

    local stderr = Stderr.collector()

    local context = {
        program = program,
        search_dir = search_dir,
        max_results = config.search.max_results,
        running = 0,
        reader_status = ReaderStatus.Reading,
        stderr = stderr,
        command_pipelines = {},
        output_pipeline_ids = {},
        pipeline_output_pending = {},
        program_output = {
            search_dir = search_dir,
            items = {},
            max_line_number = 0,
        },
        content_matches = {},
        content_exclude_line_keys = {},
        on_error = on_error,
        on_success = on_success,
    }

    if program.output_kind == OutputKind.FileNames then
        context.pipeline_output_parser = pipeline_output_parse_filenames
    else
        context.pipeline_output_parser = pipeline_output_parse_json_lines
    end

    context = setmetatable(context, { __index = RunningContext })

    for i, output_commands in ipairs(program.output_commands) do
        local pipeline = Pipeline.run {
            role = Pipeline.PipelineRole.Match,
            workdir = search_dir,
            commands = output_commands,
            stderr = stderr,

            on_exit = function(_, _, success)
                on_exit_handler(context, success)
            end,

            on_data = function(pl, data)
                results_collector(context, pl, data)
            end,
        }

        context.command_pipelines[i] = pipeline
        table.insert(context.output_pipeline_ids, pipeline.id)
    end

    if program.exclude_command then
        local pipeline = Pipeline.run {
            role = Pipeline.PipelineRole.Exclude,
            workdir = search_dir,
            commands = { program.exclude_command },
            open_stdin = true,
            stderr = stderr,

            on_exit = function(_, _, _)
                on_exit_handler(context, true)
            end,

            on_data = function(pipeline, data)
                process_exclude_content_filter(context, pipeline, data)
            end,
        }

        assert(pipeline.stdin)
        context.content_exclude_pipe = pipeline.stdin
        table.insert(context.command_pipelines, pipeline)
    end

    stderr:close_write()

    return context
end

return M
