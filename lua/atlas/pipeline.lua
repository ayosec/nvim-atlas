local parser = require("atlas.filter_parser")

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

--- Build a pipeline with `rg` commands from a specifiers list.
---
---@param specs FilterSpec[]
---@param config AtlasConfig
---@return Pipeline
function M.build(specs, config)
    local commands = {}
    local pipeline_output = M.PipeOutput.FileNames

    -- The first command is always to generate the file list.
    local file_list = {
        config.programs.ripgrep,
        "--no-messages",
        "--null",
        "--files",
    }

    if config.files.hidden then
        table.insert(file_list, "--hiden")
    end

    for _, exclude_glob in ipairs(config.files.exclude_always) do
        table.insert(file_list, "--global")
        table.insert(file_list, "!" .. exclude_glob)
    end

    table.insert(commands, file_list)

    -- Specifiers against the file names are put before filters on file
    -- contents, so we have to keep the later on a separate list.

    ---@type FilterSpec[]
    local file_contents_filters = {}

    for _, spec in ipairs(specs) do
        if spec.kind == parser.FilterKind.Simple then
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
        elseif spec.kind == parser.FilterKind.FileContents then
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

            if spec.negated then
                table.insert(cmd, "--files-without-match")
            end

            if non_negated == nil and not spec.negated then
                non_negated = cmd
            else
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
