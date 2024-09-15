local M = {}

local NS = vim.api.nvim_create_namespace("Atlas/Results")

---@param bufnr integer
---@param foldstart integer
---@param foldend integer
local function foldtext(bufnr, foldstart, foldend)
    local finder = vim.b[bufnr].AtlasFinder() ---@type atlas.Finder

    local item = finder.items_index[foldstart]
    if item == nil then
        return ""
    end

    local cw = 1
    local _, firstcol = vim.spairs(item.row_text)()
    for _, chunk in pairs(firstcol) do
        cw = cw + vim.api.nvim_strwidth(chunk[1])
    end

    return {
        { string.rep(" ", cw), "Normal" },
        { string.format("(+%d)", foldend - foldstart), "AtlasResultsFoldSize" },
    }
end

---@class atlas.impl.RenderState
---@field column_widths integer[]
---@field rows table<integer, atlas.view.bufdata.Column[]>
---@field folds table<integer, integer>
---@field skip_lines_start integer
---@field skip_lines_end integer

--- Configure the options and the syntax for the results buffer.
---
---@param bufnr integer
function M.configure_buffer(bufnr)
    vim.bo[bufnr].filetype = "AtlasResults"

    vim.api.nvim_buf_call(bufnr, function()
        vim.opt_local.fillchars:append("fold: ")

        -- Hide everything.
        vim.cmd.syntax("region", "AtlasResultsMetadata", "start=/^/", "end=/$/", "conceal")
    end)
end

---@param config atlas.Config
---@param geometry atlas.view.geometry.Geometry
---@param bufnr integer
---@return integer
function M.create_window(config, geometry, bufnr)
    local cfg = config.view.results

    local window = vim.api.nvim_open_win(bufnr, false, geometry.results)
    local wo = vim.wo[window]

    vim.w[window].AtlasFoldText = function(foldstart, foldend)
        return foldtext(bufnr, foldstart, foldend)
    end

    local winhighlight = "Normal:AtlasResultsWindow,Folded:AtlasResultsFoldText"

    if vim.fn.hlexists("AtlasResultsCursorLine") == 1 then
        winhighlight = winhighlight .. ",CursorLine:AtlasResultsCursorLine"
    end

    wo.concealcursor = "nv"
    wo.conceallevel = 2
    wo.cursorline = true
    wo.foldlevel = 32
    wo.foldmethod = "marker"
    wo.foldtext = [[w:AtlasFoldText(v:foldstart, v:foldend)]]
    wo.winhighlight = winhighlight
    wo.wrap = false

    ---@diagnostic disable-next-line:inject-field
    wo.winfixbuf = true

    if cfg.selection_mark ~= nil then
        vim.w[window].AtlasStatusColumn = function(lnum, relnum)
            local mark
            if relnum > 0 then
                ---@type atlas.Finder
                ---@diagnostic disable-next-line:undefined-field
                local finder = vim.b.AtlasFinder()

                local _, id = finder:get_item(lnum)

                if id and finder.marks.items[id] then
                    mark = "+"
                else
                    mark = " "
                end
            else
                mark = cfg.selection_mark or " "
            end

            return string.format("%%#%s#%s", cfg.selection_mark_highlight, mark)
        end

        wo.statuscolumn = [[%{%w:AtlasStatusColumn(v:lnum, v:relnum)%}]]
    end

    return window
end

---@param bufnr integer
---@param columns_gap integer
---@param lines string[]
---@param items atlas.view.bufdata.ItemIndex
---@return { row_select: integer|nil }
function M.set_content(bufnr, columns_gap, lines, items)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    -- Add extmarks to display the content.
    --
    -- First, compute the width for each column. Then, add the chunks for
    -- each column as virtual text.

    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)

    local column_widths_text = {}
    local column_widths_no_text = {}
    local row_select = nil

    for _, item in pairs(items) do
        local column_widths
        if item.item.text or item.item.line then
            column_widths = column_widths_text
        else
            column_widths = column_widths_no_text
        end

        for numcol, column in pairs(item.row_text) do
            local cw = 0
            for _, chunk in ipairs(column) do
                cw = cw + vim.api.nvim_strwidth(chunk[1])
            end

            if cw > (column_widths[numcol] or -1) then
                column_widths[numcol] = cw
            end
        end
    end

    for item_id, item in pairs(items) do
        local column_widths
        if item.item.text or item.item.line then
            column_widths = column_widths_text
        else
            column_widths = column_widths_no_text
        end

        local text_column = 0
        for colname, column_width in vim.spairs(column_widths) do
            local column = item.row_text[colname]
            if column then
                vim.api.nvim_buf_set_extmark(bufnr, NS, item_id - 1, 0, {
                    virt_text = column,
                    virt_text_win_col = text_column,
                    hl_mode = "combine",
                })
            end

            text_column = text_column + column_width + columns_gap
        end

        if row_select == nil and vim.tbl_isempty(item.item.children) then
            row_select = item_id
        end
    end

    vim.api.nvim_exec_autocmds("TextChanged", {
        buffer = bufnr,
        modeline = false,
    })

    return {
        row_select = row_select,
    }
end

return M
