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
        ["<C-c>"] = actions.destroy(),
        ["<C-f>"] = actions.toggle_fold(),
        ["<C-q>"] = actions.send_qflist(),
        ["<Cr>"] = actions.accept(),
        ["<Down>"] = actions.selection_go(1),
        ["<Up>"] = actions.selection_go(-1),
    },
}

--- Apply the keymap to an existing buffer.
---
--- The mappings are combined with the default keymap, unless a specific
--- keymap is explicitly disabled with the `false` value.
---
---@param instance atlas.Instance
---@param bufnr any
---@param keymap atlas.KeyMappings
function M.apply_keymap(instance, bufnr, keymap)
    ---@type atlas.KeyMappings
    keymap = vim.tbl_deep_extend("force", {}, Default, keymap)

    local opts = { buffer = bufnr, silent = true }

    for mode, seqs in pairs(keymap) do
        for seq, handler in pairs(seqs) do
            if handler then
                vim.keymap.set(mode, seq, function()
                    return handler(instance)
                end, opts)
            end
        end
    end
end

return M
