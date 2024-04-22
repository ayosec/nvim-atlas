local M = {}

local function default_highlights()
    local default_links = {
        AtlasResultsFold = "Comment",
        AtlasResultsItemDirectory = "Directory",
        AtlasResultsMatchLineNumber = "LineNr",
        AtlasResultsMatchText = "String",
        AtlasResultsWindow = "Normal",
    }

    for from, to in pairs(default_links) do
        vim.api.nvim_set_hl(0, from, { link = to, default = true })
    end

    vim.api.nvim_set_hl(0, "AtlasResultsTreeMarker", {
        fg = "#777777",
        ctermfg = 7,
        default = true,
    })
end

--- Configure the options and the syntax for the results buffer.
---
---@param bufnr integer
function M.configure_buffer(bufnr)
    vim.api.nvim_buf_call(bufnr, function()
        default_highlights()

        vim.opt_local.fillchars:append("fold: ")

        -- Create a region for each item kind.
        for key, value in pairs(require("atlas.view").ItemKind) do
            vim.cmd.syntax(
                "region",
                "AtlasResultsItem" .. key,
                "start=|^" .. value .. "|",
                "end=/$/",
                "keepend",
                "contains=AtlasResultsMetadata,AtlasResultsTreeMarker"
            )
        end

        vim.cmd.syntax("region", "AtlasResultsMetadata", "start=/^/", "end=/ /", "conceal", "contained")

        -- Line numbers: `@<line>`
        vim.cmd.syntax(
            "match",
            "AtlasMatchLineNumberPre",
            "/@/",
            "conceal",
            "nextgroup=AtlasResultsMatchLineNumber",
            "containedin=AtlasResultsItemContentMatch"
        )

        vim.cmd.syntax(
            "match",
            "AtlasResultsMatchLineNumber",
            [[/[0-9]\+/]],
            "contained",
            "nextgroup=AtlasResultsMatchTextPre"
        )

        -- Matched text: `: <text>`
        vim.cmd.syntax(
            "match",
            "AtlasResultsMatchTextPre",
            "/:/",
            "conceal",
            "nextgroup=AtlasResultsMatchText",
            "containedin=AtlasResultsItemContentMatch"
        )

        -- Tree markers
        vim.cmd.syntax("match", "AtlasResultsTreeMarker", "/[─│└├]/", "contained")

        vim.cmd.syntax("region", "AtlasResultsMatchText", "start=/./", "end=/$/", "contained")
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

    local winhighlight = "Normal:AtlasResultsWindow,Folded:AtlasResultsFold"

    if vim.fn.hlexists("AtlasResultsCursorLine") == 1 then
        winhighlight = winhighlight .. ",CursorLine:AtlasResultsCursorLine"
    end

    wo.concealcursor = "nv"
    wo.conceallevel = 2
    wo.cursorline = true
    wo.foldlevel = 32
    wo.foldmethod = "marker"
    wo.foldtext = [[v:lua.require("atlas.view.results").__foldtext(v:foldstart, v:foldend)]]
    wo.winhighlight = winhighlight
    wo.wrap = false

    if cfg.selection_mark ~= nil then
        wo.statuscolumn = "%#"
            .. cfg.selection_mark_highlight
            .. [[#%{ v:relnum ? " " : "]]
            .. vim.fn.escape(cfg.selection_mark, [["'\]])
            .. [[" }]]
    end

    return window
end

function M.__foldtext(foldstart, foldend)
    local range = string.format(" (+%d)", foldend - foldstart)

    local line = unpack(vim.api.nvim_buf_get_lines(0, foldstart - 1, foldstart, false))
    if not vim.startswith(line, "##") then
        return range
    end

    local end_metadata = line:find("##", 3)
    return line:sub(end_metadata + 3) .. range
end

return M
