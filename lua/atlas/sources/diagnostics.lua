local M = {}

local SEVERITY_LABELS = { "Error", "Warn", "Info", "Hint" }

---@return atlas.sources.Response
function M.diagnostics()
    ---@type atlas.searchprogram.ResultItem[]
    local items = {}

    local bufnames = {}

    for _, diagnostic in ipairs(vim.diagnostic.get()) do
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
