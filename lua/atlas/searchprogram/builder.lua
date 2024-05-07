local M = {}

local FIFOStdinMark = require("atlas.searchprogram").FIFOStdinMark
local FilterKind = require("atlas.filter").FilterKind
local OutputKind = require("atlas.searchprogram").OutputKind

--- Commands to apply a filter.
---
---@class atlas.searchprogram.Program
---@field output_kind atlas.searchprogram.OutputKind
---@field output_commands atlas.searchprogram.Command[]
---@field exclude_command? string[]

--- Extend the main command of the pipeline from configuration.
---
---@param command string[]
---@param config atlas.Config
local function prepare_entrypoint(command, config)
    if config.files.hidden then
        table.insert(command, "--hidden")
    end

    for _, exclude_glob in ipairs(config.files.exclude_always) do
        table.insert(command, "--glob")
        table.insert(command, "!" .. exclude_glob)
    end
end

---@param config atlas.Config
---@return string
local function case_sensitivity_argument(config)
    if config.search.case_sensitivity == "smart" then
        return "--smart-case"
    elseif config.search.case_sensitivity then
        return "--case-sensitive"
    else
        return "--ignore-case"
    end
end

---@param spec atlas.filter.Spec
---@return string
local function spec_to_regex(spec)
    if spec.fixed_string then
        return vim.fn.escape(spec.value, "\\.+*?()|[]{}^$&-~")
    else
        return spec.value
    end
end

---@param config atlas.Config
---@param exclude_specs atlas.filter.Spec[]
---@param emit_files boolean
---@return string[]
local function exclude_command_from_specs(config, exclude_specs, emit_files)
    local cmd = {}

    if emit_files then
        vim.list_extend(cmd, {
            config.programs.xargs,
            "--null",
        })
    end

    vim.list_extend(cmd, {
        config.programs.ripgrep,
        case_sensitivity_argument(config),
        "--no-config",
        "--no-messages",
    })

    if emit_files then
        vim.list_extend(cmd, {
            "--null",
            "--files-without-match",
        })
    else
        -- Collect only line numbers when this ripgrep instance is
        -- used to filter another pipeline.
        vim.list_extend(cmd, {
            "--line-number",
            "--max-columns=1",
            "--null-data",
        })
    end

    -- All regexps can be put in a single command. Ripgrep will discard
    -- the file if any of the regexps is found.
    for _, spec in pairs(exclude_specs) do
        table.insert(cmd, "--regexp")
        table.insert(cmd, spec_to_regex(spec))
    end

    return cmd
end

--- Specialized case when the filter is a single FileContents specifier.
---
---@param spec atlas.filter.Spec
---@param config atlas.Config
---@return atlas.searchprogram.Program
local function specialized_single_file_contents(spec, config)
    local output_kind

    local cmd = {
        config.programs.ripgrep,
        case_sensitivity_argument(config),
        "--no-config",
        "--no-messages",
        "--null",
        "--regexp",
        spec.value,
    }

    if spec.fixed_string then
        table.insert(cmd, "--fixed-strings")
    end

    prepare_entrypoint(cmd, config)

    if spec.exclude then
        output_kind = OutputKind.FileNames
        table.insert(cmd, "--files-without-match")
    else
        output_kind = OutputKind.JsonLines
        table.insert(cmd, "--json")
    end

    ---@type atlas.searchprogram.Program
    local program = {
        output_commands = { { cmd } },
        output_kind = output_kind,
    }

    return program
end

---@param config atlas.Config
---@param count integer
---@return string[]
local function try_mkfifo(config, count)
    if count < 1 then
        return {}
    end

    local command = { config.programs.mkfifo }
    local paths = {}

    for _ = 1, count do
        local path = vim.fn.tempname()
        table.insert(command, path)
        table.insert(paths, path)
    end

    local ok, _ = pcall(vim.fn.system, command)

    if ok and vim.v.shell_error == 0 then
        return paths
    end

    return {}
end

--- Build a pipeline with `rg` commands from a specifiers list.
---
---@param specs atlas.filter.Spec[]
---@param config atlas.Config
---@return atlas.searchprogram.Program
function M.build(specs, config)
    ---@type atlas.searchprogram.OutputKind
    local output_kind = OutputKind.FileNames

    ---@type atlas.searchprogram.Command[]
    local output_commands = {}

    ---@type atlas.searchprogram.Command
    local filelist_commands = {}

    -- If the filter is a single spec for FileContents, the pipeline is a
    -- single rg(1) command.
    if #specs == 1 and specs[1].kind == FilterKind.FileContents then
        return specialized_single_file_contents(specs[1], config)
    end

    -- The first command is always to generate the file list.
    local file_list = {
        config.programs.ripgrep,
        case_sensitivity_argument(config),
        "--no-config",
        "--no-messages",
        "--null",
        "--files",
    }

    prepare_entrypoint(file_list, config)

    table.insert(filelist_commands, file_list)

    -- Specifiers against the file names are put before filters on file
    -- contents, so we have to keep the later on a separate list.

    local content_filters = {} ---@type atlas.filter.Spec[]
    local exclude_content_filters = {} ---@type atlas.filter.Spec[]
    local exclude_command = nil ---@type nil|string[]

    for _, spec in ipairs(specs) do
        if spec.kind == FilterKind.Simple then
            local cmd = {
                config.programs.ripgrep,
                case_sensitivity_argument(config),
                "--no-config",
                "--no-messages",
                "--null-data",
                "--regexp",
                spec.value,
            }

            if spec.fixed_string then
                table.insert(cmd, "--fixed-strings")
            end

            if spec.exclude then
                table.insert(cmd, "--invert-match")
            end

            table.insert(filelist_commands, cmd)
        elseif spec.kind == FilterKind.FileContents then
            if spec.exclude then
                table.insert(exclude_content_filters, spec)
            else
                table.insert(content_filters, spec)
            end
        else
            error("Invalid spec: " .. vim.inspect(spec))
        end
    end

    -- If there are `exclude_content_filters`, but no `content_filters`, the
    -- pipeline only need to discard files where the `exclude_content_filters`
    -- are found, so it is enough with adding a `--files-without-match`.
    if #content_filters == 0 and #exclude_content_filters > 0 then
        local cmd = exclude_command_from_specs(config, exclude_content_filters, true)
        table.insert(filelist_commands, cmd)
    end

    -- Filters on file contents.
    --
    -- The first non-excluded filter will be used to emit positions info.
    if #content_filters > 0 then
        local fifos = try_mkfifo(config, #content_filters - 1)

        output_kind = OutputKind.JsonLines

        if #fifos > 0 then
            local cmd = { config.programs.tee }
            vim.list_extend(cmd, fifos)
            table.insert(filelist_commands, cmd)
        end

        for num_spec, spec in ipairs(content_filters) do
            local cmd = {
                config.programs.xargs,
                "--null",
                config.programs.ripgrep,
                case_sensitivity_argument(config),
                "--no-config",
                "--no-messages",
                "--null",
                "--json",
                "--regexp",
                spec.value,
            }

            if spec.fixed_string then
                table.insert(cmd, "--fixed-strings")
            end

            local filelist_cmd
            if num_spec == 1 or #fifos == 0 then
                filelist_cmd = vim.deepcopy(filelist_commands)
            else
                filelist_cmd = { { FIFOStdinMark, fifos[num_spec - 1] } }
            end

            table.insert(filelist_cmd, cmd)
            table.insert(output_commands, filelist_cmd)
        end

        -- Exclude-content filters
        if #exclude_content_filters > 0 then
            exclude_command = exclude_command_from_specs(config, exclude_content_filters, false)
        end
    end

    if vim.tbl_isempty(output_commands) then
        output_commands = { filelist_commands }
    end

    ---@type atlas.searchprogram.Program
    local program = {
        output_kind = output_kind,
        output_commands = output_commands,
        exclude_command = exclude_command,
    }

    return program
end

return M
