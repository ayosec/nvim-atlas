local M = {}

local actions = require("atlas.actions")

---@type atlas.KeyMappings
local Default = {
    i = {
        ["<C-r><C-f>"] = actions.expand_last_cfile(),
        ["<C-r><C-w>"] = actions.expand_last_cword(),
    },

    n = {
        ["<Esc>"] = actions.destroy(),
    },

    [{ "i", "n", "s" }] = {
        ["<C-Down>"] = actions.history_go(-1),
        ["<C-Up>"] = actions.history_go(1),
        ["<C-a>"] = actions.selection_toggle_mark("all"),
        ["<C-c>"] = actions.destroy(),
        ["<C-f>"] = actions.toggle_fold(),
        ["<C-p>"] = actions.toggle_preview(),
        ["<C-q>"] = actions.send_qflist(),
        ["<Cr>"] = actions.accept(),
        ["<Down>"] = actions.selection_go(1),
        ["<F1>"] = actions.toggle_help(),
        ["<PageDown>"] = actions.move_pages(1),
        ["<PageUp>"] = actions.move_pages(-1),
        ["<Tab>"] = actions.selection_toggle_mark("current"),
        ["<Up>"] = actions.selection_go(-1),
    },
}

--- Apply the keymap to an existing buffer.
---
--- The mappings are combined with the default keymap, unless a specific
--- keymap is explicitly disabled with the `false` value.
---
---@param finder atlas.Finder
---@param bufnr any
---@param keymap atlas.KeyMappings
function M.apply_keymap(finder, bufnr, keymap)
    ---@type atlas.KeyMappings
    keymap = vim.tbl_deep_extend("force", {}, Default, keymap)

    local opts = { buffer = bufnr, silent = true }

    for mode, maps in pairs(keymap) do
        for seq, map in pairs(maps) do
            if map then
                vim.keymap.set(mode, seq, function()
                    return map.handler(finder)
                end, opts)
            end
        end
    end

    finder.help.keymap = keymap
end

return M
