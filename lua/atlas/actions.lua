local M = {}

local ItemKind = require("atlas.view").ItemKind

---@param instance atlas.Instance
---@param command string
local function exec_normal(instance, command)
    vim.api.nvim_buf_call(instance.view.results_buffer, function()
        vim.cmd.normal { args = { command }, bang = true }
    end)
end

--- If the selected entry is a directory, toggle its contents
--- (like `toggle_fold`).
---
--- If it is a file, open the current selection.
---@return atlas.KeyMapHandler
function M.accept()
    return function(instance)
        local selected = instance:get_selected_item()
        if not selected then
            return
        end

        if selected.kind == ItemKind.Directory then
            return M.toggle_fold()(instance)
        end

        instance:accept()
    end
end

--- Close all windows related to this instance.
---@return atlas.KeyMapHandler
function M.destroy()
    return function(instance)
        instance:destroy()
    end
end

--- Move the selection `n` rows.
---
--- If `n` is negative, the selection moves upwards.
---@param n integer
---@return atlas.KeyMapHandler
function M.selection_go(n)
    local move_cmd
    if n < 0 then
        move_cmd = string.format("%dk", -n)
    else
        move_cmd = string.format("%dj", n)
    end

    return function(instance)
        exec_normal(instance, move_cmd)
    end
end

---@return atlas.KeyMapHandler
function M.toggle_fold()
    return function(instance)
        exec_normal(instance, "za")
    end
end

return M
