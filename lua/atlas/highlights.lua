local M = {}

---@param items table<string, string>
local function links(items)
    for from, to in pairs(items) do
        vim.api.nvim_set_hl(0, from, { link = to, default = true })
    end
end

function M.set_defaults()
    -- Help
    links {
        AtlasHelpColumnKey = "Function",
        AtlasHelpColumnModes = "Keyword",
        AtlasHelpColumnText = "Normal",
        AtlasHelpHeader = "Title",
        AtlasHelpLiteral = "String",
        AtlasHelpWindow = "Normal",
    }

    -- Prompt
    links {
        AtlasPromptItemExclude = "Operator",
        AtlasPromptItemFixedString = "Operator",
        AtlasPromptItemRegex = "String",
        AtlasPromptItemSource = "Identifier",
        AtlasPromptPrefix = "Identifier",
        AtlasPromptWindow = "Normal",
    }

    -- Results.
    links {
        AtlasResultsDiffAdd = "DiffAdd",
        AtlasResultsDiffDelete = "DiffDelete",
        AtlasResultsFold = "Comment",
        AtlasResultsItemDirectory = "Directory",
        AtlasResultsItemFile = "Normal",
        AtlasResultsMatchHighlight = "Search",
        AtlasResultsMatchLineNumber = "LineNr",
        AtlasResultsMatchText = "String",
        AtlasResultsWindow = "Normal",
    }

    vim.api.nvim_set_hl(0, "AtlasResultsMarkedFile", {
        cterm = { bold = true },
        bold = true,
        default = true,
    })

    vim.api.nvim_set_hl(0, "AtlasResultsTreeMarker", {
        fg = "#777777",
        ctermfg = 7,
        default = true,
    })
end

return M
