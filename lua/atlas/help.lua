local M = {}

local COLUMN_GAP = 2

local COLUMNS = {
    { "MODES", "AtlasHelpColumnModes" },
    { "KEY", "AtlasHelpColumnKey" },
    { "HELP", "AtlasHelpColumnText" },
}

---@class atlas.impl.Help
---@field bufnr nil|integer
---@field keymap atlas.KeyMappings

---@param keymap atlas.KeyMappings
---@return { column_widths: integer[], lines: string[] }
local function render_help(keymap)
    local column_widths = {}

    -- Write header using the highlight groups.
    local header = {}
    for n, column in ipairs(COLUMNS) do
        header[n] = column[1]
        column_widths[n] = vim.api.nvim_strwidth(column[1]) + COLUMN_GAP
    end

    local lines = { table.concat(header, "\t") }
    for modes, keys in pairs(keymap) do
        local mode_column

        if type(modes) == "string" then
            mode_column = modes
        else
            mode_column = table.concat(modes, " ")
        end

        for key, handler in pairs(keys) do
            if handler and handler.help then
                local line = { mode_column, key, handler.help }

                for n, col in pairs(line) do
                    col = col:gsub("\1", "")
                    local width = vim.api.nvim_strwidth(col) + COLUMN_GAP
                    if width > column_widths[n] then
                        column_widths[n] = width
                    end
                end

                table.insert(lines, table.concat(line, "\t"))
            end
        end
    end

    return {
        lines = lines,
        column_widths = column_widths,
    }
end

---@param lines string[]
---@param column_widths integer[]
---@return integer
local function create_buffer(lines, column_widths)
    local bufnr = vim.api.nvim_create_buf(false, true)

    local bo = vim.bo[bufnr]
    bo.bufhidden = "wipe"
    bo.buftype = "nofile"

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    vim.bo[bufnr].vartabstop = table.concat(vim.tbl_map(tostring, column_widths), ",")

    vim.api.nvim_buf_call(bufnr, function()
        -- Convert tabs to spaces, so the highlight can be applied in columns.
        vim.cmd.retab()

        -- Sort by the second column,
        vim.cmd.sort {
            args = { string.format([[/\%%%dv/]], column_widths[1]) },
            range = { 2, vim.fn.line("$") },
        }

        vim.cmd.syntax("match", "AtlasHelpHeader", [[/\%1l.*/]])

        local position = 0
        for n, column in ipairs(COLUMNS) do
            local next_pos = position + column_widths[n]
            vim.cmd.syntax("match", column[2], string.format([[/\%%>1l\%%>%dv.*\%%<%dv/]], position, next_pos))

            position = next_pos
        end

        -- Literal values in Text column, between `\x01` bytes.
        vim.cmd.syntax("match", "AtlasHelpLiteral", "/\1.*\1/", "containedin=AtlasHelpColumnText")

        vim.cmd.syntax("match", "AtlasHelpLiteralDelim", "/\1/", "containedin=AtlasHelpLiteral", "conceal")
    end)

    return bufnr
end

---@param bufnr integer
---@param width integer
---@param height integer
local function create_window(bufnr, width, height)
    local opts = {
        col = 2,
        row = 2,
        width = width,
        height = height,
        relative = "editor",
        style = "minimal",
        border = "single",
    }

    local window = vim.api.nvim_open_win(bufnr, false, opts)

    local wo = vim.wo[window]
    wo.concealcursor = "nv"
    wo.conceallevel = 2
end

---@param finder atlas.Finder
function M.toggle(finder)
    local help = finder.help

    if help.bufnr then
        M.destroy(finder)
        return
    end

    local render = render_help(help.keymap)
    help.bufnr = create_buffer(render.lines, render.column_widths)

    local width = -COLUMN_GAP
    for _, cw in pairs(render.column_widths) do
        width = width + cw
    end

    create_window(help.bufnr, width, #render.lines)
end

---@param finder atlas.Finder
function M.destroy(finder)
    local help = finder.help
    if help.bufnr and vim.api.nvim_buf_is_valid(help.bufnr) then
        vim.api.nvim_buf_delete(help.bufnr, { force = true })
    end

    help.bufnr = nil
end

return M
