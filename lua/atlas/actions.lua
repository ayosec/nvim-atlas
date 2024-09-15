local M = {}

local Geometry = require("atlas.view.geometry")
local Help = require("atlas.help")
local ItemKind = require("atlas.view").ItemKind
local Preview = require("atlas.preview")
local Text = require("atlas.text")

local NS_MARKED_FILES = require("atlas.view.bufdata").NS_MARKED_FILES

---@param finder atlas.Finder
---@param callback fun()
local function results_call(finder, callback)
    vim.api.nvim_buf_call(finder.view.results_buffer, function()
        callback()
    end)
end

---@param finder atlas.Finder
---@param delta integer
---@return boolean
local function move_cursor_row(finder, delta)
    local view = finder.view

    local num_lines = vim.api.nvim_buf_line_count(view.results_buffer)
    local current_row = vim.api.nvim_win_get_cursor(view.results_window)[1]

    local row = current_row + delta

    -- Select only nodes with no children, or the start of a fold.
    local adjdelta = delta < 0 and -1 or 1
    while row >= 1 and row <= num_lines do
        local fold = -1
        vim.api.nvim_buf_call(finder.view.results_buffer, function()
            fold = vim.fn.foldclosed(row)
        end)

        if fold > 0 then
            if fold == row then
                -- At the start of the fold.
                break
            end
        else
            local item = finder:get_item(row)
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
---@param use_tabs boolean
---@return atlas.KeyMapHandler
function M.accept(use_tabs)
    local help = "Open the selected file" .. (use_tabs and " in a new tab." or ".")

    return {
        help = help,
        handler = function(finder)
            local selected = finder:get_selected_item()
            if not selected then
                return
            end

            if selected.kind == ItemKind.Directory then
                return M.toggle_fold().handler(finder)
            end

            finder:accept(use_tabs)
        end,
    }
end

--- Close all windows for this instance.
---@return atlas.KeyMapHandler
function M.destroy()
    return {
        help = "Close the current finder.",
        handler = function(finder)
            finder:destroy(false)
        end,
    }
end

---@return atlas.KeyMapHandler
function M.expand_last_cfile()
    return {
        help = "Insert original \1<cfile>\1.",
        handler = function(finder)
            vim.api.nvim_feedkeys(finder.original_environment.cfile, "n", false)
        end,
    }
end

---@return atlas.KeyMapHandler
function M.expand_last_cword()
    return {
        help = "Insert original \1<cword>\1.",
        handler = function(finder)
            vim.api.nvim_feedkeys(finder.original_environment.cword, "n", false)
        end,
    }
end

---@param delta 1|-1
---@return atlas.KeyMapHandler
function M.history_go(delta)
    return {
        help = string.format("Set prompt to %s history entry.", delta == -1 and "next" or "previous"),
        handler = function(finder)
            local entry = finder.history:go(delta)
            if entry then
                -- Save the current prompt on the first change.
                if finder.state.history_initial_prompt == nil then
                    finder.state.history_initial_prompt = finder:get_prompt()
                end

                finder:set_prompt(entry)
            elseif delta < 1 then
                -- Restore prompt if we return to it.
                entry = finder.state.history_initial_prompt
                if entry then
                    finder:set_prompt(entry)
                    finder.state.history_initial_prompt = nil
                end
            end
        end,
    }
end

---@param direction 1|-1
---@return atlas.KeyMapHandler
function M.move_pages(direction)
    return {
        help = string.format("%s results page.", direction == -1 and "Previous" or "Next"),
        handler = function(finder)
            local height = vim.api.nvim_win_get_height(finder.view.results_window)
            move_cursor_row(finder, height * direction)
        end,
    }
end

--- Resize the view.
---@param delta integer
---@return atlas.KeyMapHandler
function M.resize(delta)
    return {
        help = string.format("%s view height.", delta < 0 and "Decrease" or "Increase"),
        handler = function(finder)
            local height = finder.view.config.view.height

            if type(height) == "number" then
                height = math.max(height + delta, 5)
            elseif type(height) == "string" then
                local _, _, percent = height:find("^(%d+)%%$")
                if percent then
                    height = string.format("%d%%", math.max(tonumber(percent) + delta, 5))
                end
            else
                return
            end

            finder.view.config.view.height = height
            Geometry.resize_instance(finder.view)
        end,
    }
end

--- Move the selection `n` rows.
---
--- If `n` is negative, the selection moves upwards.
---@param n integer
---@return atlas.KeyMapHandler
function M.selection_go(n)
    return {
        help = string.format(
            "Move selection %d row%s %s.",
            math.abs(n),
            math.abs(n) == 1 and "" or "s",
            n < 0 and "up" or "down"
        ),
        handler = function(finder)
            move_cursor_row(finder, n)
        end,
    }
end

---@param scope "all"|"current"
---@return atlas.KeyMapHandler
function M.selection_toggle_mark(scope)
    return {
        help = string.format("Mark/unmark %s.", scope == "all" and "all items" or "selected item"),
        handler = function(finder)
            local marks = finder.marks
            local bufnr = finder.view.results_buffer

            local function mark(id, item, marked)
                if vim.tbl_isempty(item.children) then
                    if marked then
                        marks.items[id] = true
                        vim.api.nvim_buf_set_extmark(bufnr, NS_MARKED_FILES, id - 1, 0, {
                            id = id,
                            line_hl_group = "AtlasResultsMarkedFile",
                        })
                    else
                        marks.items[id] = nil
                        vim.api.nvim_buf_del_extmark(bufnr, NS_MARKED_FILES, id)
                    end
                end
            end

            if scope == "all" then
                marks.all = not marks.all
                local marked = marks.all

                for id, item_data in pairs(finder.items_index) do
                    mark(id, item_data.item, marked)
                end
            end

            if scope == "current" then
                local item, id = finder:get_selected_item()
                if id and item then
                    mark(id, item, not marks.items[id])
                end

                move_cursor_row(finder, 1)
            end
        end,
    }
end

--- Send the current tree to the quickfix list.
---
--- If there are marked files, only those are sent to the list.
---
---@return atlas.KeyMapHandler
function M.send_qflist()
    return {
        help = "Send current results to quickfix list.",
        handler = function(finder)
            local mark_items = finder.marks.items
            local no_marks = vim.tbl_isempty(mark_items)

            local qf_items = {}
            for item_id, item_data in ipairs(finder.items_index) do
                local item = item_data.item

                local may_open = no_marks or mark_items[item_id]

                if may_open and vim.tbl_isempty(item.children) then
                    local qf_item = {
                        filename = finder:item_path(item),
                        lnum = item.line,
                        text = item.text,
                    }

                    table.insert(qf_items, qf_item)
                end
            end

            finder:destroy(true)

            vim.fn.setqflist(qf_items, " ")
            vim.cmd.copen()
        end,
    }
end

---@return atlas.KeyMapHandler
function M.toggle_fold()
    ---@return number
    local function foldlevel()
        ---@diagnostic disable-next-line:param-type-mismatch
        return vim.fn.foldclosed(".")
    end

    return {
        help = "Expand/collapse current subtree.",
        handler = function(finder)
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

            results_call(finder, function()
                if foldlevel() == -1 then
                    vim.cmd("normal! zc")

                    if foldlevel() == -1 then
                        -- If it is still open, another `zc` to close its parent.
                        vim.cmd("normal! zc")
                    end

                    -- Ensure cursor is at the start of the fold.
                    if foldlevel() ~= vim.fn.line(".") then
                        move_cursor_row(finder, -1)
                    end
                else
                    vim.cmd("normal! zo")
                end
            end)
        end,
    }
end

---@return atlas.KeyMapHandler
function M.toggle_help()
    return {
        help = "Toggle help window.",
        handler = Help.toggle,
    }
end

---@return atlas.KeyMapHandler
function M.toggle_preview()
    return {
        help = "Toggle preview file window.",
        handler = Preview.toggle,
    }
end

--- Add or remove a fragment from the prompt.
---
---@param fragment string
---@return atlas.KeyMapHandler
function M.toggle_text(fragment)
    return {
        help = string.format("Add or remove the fragment \1%s\1.", fragment),
        handler = function(finder)
            finder:set_prompt(Text.toggle(finder:get_prompt(), fragment))
        end,
    }
end

return M
