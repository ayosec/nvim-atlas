local M = {}

local ItemKind = require("atlas.view").ItemKind
local Preview = require("atlas.preview")
local Text = require("atlas.text")

---@param instance atlas.Instance
---@param callback fun()
local function results_call(instance, callback)
    vim.api.nvim_buf_call(instance.view.results_buffer, function()
        callback()
    end)
end

---@param instance atlas.Instance
---@param delta integer
---@return boolean
local function move_cursor_row(instance, delta)
    local view = instance.view

    local num_lines = vim.api.nvim_buf_line_count(view.results_buffer)
    local current_row = vim.api.nvim_win_get_cursor(view.results_window)[1]

    local row = current_row + delta

    -- Select only nodes with no children, or the start of a fold.
    local adjdelta = delta < 0 and -1 or 1
    while row >= 1 and row <= num_lines do
        local fold = -1
        vim.api.nvim_buf_call(instance.view.results_buffer, function()
            fold = vim.fn.foldclosed(row)
        end)

        if fold > 0 then
            if fold == row then
                -- At the start of the fold.
                break
            end
        else
            local item = instance:get_item(row)
            if item and (item.kind == ItemKind.Directory or vim.tbl_isempty(item.children)) then
                break
            end
        end

        row = row + adjdelta
    end

    row = math.min(math.max(row, 1), num_lines)

    if row == current_row then
        -- Cursor was not moved.
        return false
    end

    vim.api.nvim_win_set_cursor(view.results_window, { row, 0 })

    vim.api.nvim_exec_autocmds("CursorMoved", {
        buffer = view.results_buffer,
        modeline = false,
    })

    return true
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

--- Close all windows for this instance.
---@return atlas.KeyMapHandler
function M.destroy()
    return function(instance)
        instance:destroy(false)
    end
end

---@return atlas.KeyMapHandler
function M.expand_last_cfile()
    return function(instance)
        vim.api.nvim_feedkeys(instance.original_environment.cfile, "n", false)
    end
end

---@return atlas.KeyMapHandler
function M.expand_last_cword()
    return function(instance)
        vim.api.nvim_feedkeys(instance.original_environment.cword, "n", false)
    end
end

---@param delta integer
---@return atlas.KeyMapHandler
function M.history_go(delta)
    return function(instance)
        local entry = instance.history:go(delta)
        if entry then
            -- Save the current prompt on the first change.
            if instance.state.history_initial_prompt == nil then
                instance.state.history_initial_prompt = instance:get_prompt()
            end

            instance:set_prompt(entry)
        elseif delta < 1 then
            -- Restore prompt if we return to it.
            entry = instance.state.history_initial_prompt
            if entry then
                instance:set_prompt(entry)
                instance.state.history_initial_prompt = nil
            end
        end
    end
end

---@param direction 1|-1
---@return atlas.KeyMapHandler
function M.move_pages(direction)
    return function(instance)
        local height = vim.api.nvim_win_get_height(instance.view.results_window)
        move_cursor_row(instance, height * direction)
    end
end

--- Move the selection `n` rows.
---
--- If `n` is negative, the selection moves upwards.
---@param n integer
---@return atlas.KeyMapHandler
function M.selection_go(n)
    return function(instance)
        move_cursor_row(instance, n)
    end
end

---@param scope "all"|"current"
---@return atlas.KeyMapHandler
function M.selection_toggle_mark(scope)
    return function(instance)
        local marks = instance.marks

        if scope == "all" then
            marks.all = not marks.all
            local marked = marks.all

            for id, item_data in pairs(instance.items_index) do
                if vim.tbl_isempty(item_data.item.children) then
                    marks.items[id] = marked
                end
            end
        end

        if scope == "current" then
            local item, id = instance:get_selected_item()
            if id and item and vim.tbl_isempty(item.children) then
                if marks.items[id] then
                    marks.items[id] = nil
                else
                    marks.items[id] = true
                end
            end

            move_cursor_row(instance, 1)
        end

        vim.cmd.redraw { bang = true }
    end
end

--- Send the current tree to the quickfix list.
---
---@return atlas.KeyMapHandler
function M.send_qflist()
    return function(instance)
        local qf_items = {}
        for _, item_data in ipairs(instance.items_index) do
            local item = item_data.item
            if vim.tbl_isempty(item.children) then
                local qf_item = {
                    filename = instance:item_path(item),
                    lnum = item.line,
                    text = item.text,
                }

                table.insert(qf_items, qf_item)
            end
        end

        instance:destroy(true)

        vim.fn.setqflist(qf_items, " ")
        vim.cmd.copen()
    end
end

---@return atlas.KeyMapHandler
function M.toggle_fold()
    return function(instance)
        -- The `za` Normal command should be enough to toggle the fold.
        -- However, if the user tries to toggle a fold with no children,
        -- `za` will close it instead of its parent. This does not have
        -- any visible effect, and can be confusing.
        --
        -- To avoid the issue, `foldclosed` is used to check the status
        -- of the fold in the current line:
        --
        -- - If it is closed: open it.
        -- - If it is not closed, close it and verify that it is closed.

        results_call(instance, function()
            if vim.fn.foldclosed(".") == -1 then
                vim.cmd("normal! zc")

                if vim.fn.foldclosed(".") == -1 then
                    -- If it is still open, another `zc` to close its parent.
                    vim.cmd("normal! zc")
                end

                -- Ensure cursor is at the start of the fold.
                if vim.fn.foldclosed(".") ~= vim.fn.line(".") then
                    move_cursor_row(instance, -1)
                end
            else
                vim.cmd("normal! zo")
            end
        end)
    end
end

---@return atlas.KeyMapHandler
function M.toggle_preview()
    return Preview.toggle
end

--- Add or remove a fragment from the prompt.
---
---@param fragment string
---@return atlas.KeyMapHandler
function M.toggle_text(fragment)
    return function(instance)
        instance:set_prompt(Text.toggle(instance:get_prompt(), fragment))
    end
end

return M
