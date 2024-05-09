local M = {}

local MESSAGES_PREFIX = require("atlas.view.errors").MESSAGES_PREFIX

local SEVERITY_LABELS = { "Error", "Warn", "Info", "Hint" }

---@param argument string?
---@return atlas.sources.Response
function M.diagnostics(argument)
    ---@type atlas.searchprogram.ResultItem[]
    local items = {}

    local opts = {}

    if argument == "?" then
        opts.severity = vim.diagnostic.severity.WARN
    elseif argument == "!" then
        opts.severity = vim.diagnostic.severity.ERROR
    elseif argument ~= nil then
        error(MESSAGES_PREFIX .. "Invalid argument: " .. vim.inspect(argument))
    end

    local diagnostics = vim.diagnostic.get(nil, opts)

    table.sort(diagnostics, function(a, b)
        -- If there are multiple diagnostics in the same line,
        -- higher severity should have more priority.
        return b.severity < a.severity
    end)

    local bufnames = {}

    for _, diagnostic in ipairs(diagnostics) do
        local bufnr = diagnostic.bufnr
        local bufname = bufnames[bufnr]

        if not bufname then
            bufname = vim.api.nvim_buf_get_name(bufnr):sub(2)
            bufnames[bufnr] = bufname
        end

        local message = diagnostic.message
        local hl_group = nil

        local sl = SEVERITY_LABELS[diagnostic.severity]
        if sl then
            message = sl:sub(1, 1) .. ": " .. message
            hl_group = "Diagnostic" .. sl
        end

        table.insert(items, {
            file = bufname,
            line = diagnostic.lnum + 1,
            text = message,
            main_highlight_group = hl_group,
        })
    end

    return {
        search_dir = "/",
        items = items,
    }
end

return M
