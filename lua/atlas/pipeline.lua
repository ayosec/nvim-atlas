local FilterKind = require("atlas.filter_parser").FilterKind

local M = {}

---@enum pipeOutput
M.PipeOutput = {
    FileNames = 1,
    JsonLines = 2,
}

--- Commands to apply a filter.
---
---@class Pipeline
---@field commands string[][]
---@field output pipeOutput

--- Extend the main command of the pipeline from configuration.
---
---@param command string[]
---@param config AtlasConfig
local function prepare_entrypoint(command, config)
    if config.files.hidden then
        table.insert(command, "--hidden")
    end

    for _, exclude_glob in ipairs(config.files.exclude_always) do
        table.insert(command, "--global")
        table.insert(command, "!" .. exclude_glob)
    end
end

--- Specialized case when the filter is a single FileContents specifier.
---
---@param negated boolean
---@param value string
---@param config AtlasConfig
---@return Pipeline
local function specialized_single_file_contents(negated, value, config)
    local pipeline_output

    local cmd = {
        config.programs.ripgrep,
        "--no-messages",
        "--regexp",
        value,
    }

    prepare_entrypoint(cmd, config)

    if negated then
        pipeline_output = M.PipeOutput.FileNames
        table.insert(cmd, "--files-without-match")
    else
        pipeline_output = M.PipeOutput.JsonLines
        table.insert(cmd, "--json")
    end

    return {
        commands = { cmd },
        output = pipeline_output,
    }
end

--- Build a pipeline with `rg` commands from a specifiers list.
---
---@param specs FilterSpec[]
---@param config AtlasConfig
---@return Pipeline
function M.build(specs, config)
    local commands = {}
    local pipeline_output = M.PipeOutput.FileNames

    -- If the filter is a single spec for FileContents, the pipeline is a
    -- single rg(1) command.
    if #specs == 1 and specs[1].kind == FilterKind.FileContents then
        return specialized_single_file_contents(specs[1].negated, specs[1].value, config)
    end

    -- The first command is always to generate the file list.
    local file_list = {
        config.programs.ripgrep,
        "--no-messages",
        "--null",
        "--files",
    }

    prepare_entrypoint(file_list, config)

    table.insert(commands, file_list)

    -- Specifiers against the file names are put before filters on file
    -- contents, so we have to keep the later on a separate list.

    ---@type FilterSpec[]
    local file_contents_filters = {}

    for _, spec in ipairs(specs) do
        if spec.kind == FilterKind.Simple then
            local cmd = {
                config.programs.ripgrep,
                "--no-messages",
                "--null-data",
                "--regexp",
                spec.value,
            }

            if spec.negated then
                table.insert(cmd, "--invert-match")
            end

            table.insert(commands, cmd)
        elseif spec.kind == FilterKind.FileContents then
            table.insert(file_contents_filters, spec)
        else
            error("Invalid spec: " .. vim.inspect(spec))
        end
    end

    -- Filters on file contents.
    --
    -- The first non-negated filter will be used to emit positions info.
    if #file_contents_filters > 0 then
        local non_negated = nil

        for _, spec in ipairs(file_contents_filters) do
            local cmd = {
                config.programs.xargs,
                "--null",
                config.programs.ripgrep,
                "--no-messages",
                "--null",
                "--regexp",
                spec.value,
            }

            if non_negated == nil and not spec.negated then
                non_negated = cmd
            else
                local arg = spec.negated and "--files-without-match" or "--files-with-matches"
                table.insert(cmd, arg)
                table.insert(commands, cmd)
            end
        end

        if non_negated ~= nil then
            pipeline_output = M.PipeOutput.JsonLines
            table.insert(non_negated, "--json")
            table.insert(commands, non_negated)
        end
    end

    return {
        commands = commands,
        output = pipeline_output,
    }
end

return M
