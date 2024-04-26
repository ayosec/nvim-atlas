local M = {}

local Geometry = require("atlas.view.geometry")

local ERROR_NS = vim.api.nvim_create_namespace("Atlas/ErrorMessages")

---@class atlas.impl.FilePreviewer
---@field window integer
---@field bufnr integer
---@field filename string|nil
---@field results_watcher any

---@param filename? string
---@param filesize_limit_mb integer
---@return integer
local function buf_create(filename, filesize_limit_mb)
    -- Create a new buffer to write the data from the file.
    local bufnr = vim.api.nvim_create_buf(false, true)
    local bo = vim.bo[bufnr]
    bo.bufhidden = "wipe"
    bo.buftype = "nofile"

    if filename == nil or vim.fn.filereadable(filename) == 0 then
        return bufnr
    end

    local filesize = vim.fn.getfsize(filename) / 1048576
    if filesize >= filesize_limit_mb then
        vim.api.nvim_buf_set_extmark(bufnr, ERROR_NS, 0, 0, {
            id = 1,
            virt_text = {
                {
                    string.format("Maximum file size exceeded (%dM).", filesize),
                    "ErrorMsg",
                },
            },
            virt_text_pos = "overlay",
        })
        return bufnr
    end

    vim.api.nvim_buf_call(bufnr, function()
        local mods = {
            keepjumps = true,
            silent = true,
        }

        vim.cmd.read {
            args = { vim.fn.fnameescape(filename) },
            range = { 0 },
            mods = mods,
        }

        vim.cmd.delete { range = { vim.fn.line("$") }, mods = mods }
    end)

    local filetype = vim.filetype.match {
        buf = bufnr,
        filename = filename,
    }

    if filetype then
        vim.bo[bufnr].filetype = filetype
    end

    return bufnr
end

---@param bufnr integer
local function buf_delete(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

---@param window integer
---@param item? atlas.view.Item
local function win_config(window, item)
    local cursorline = false
    local has_numbers = false

    if item then
        vim.api.nvim_win_set_config(window, {
            title = " " .. item.path .. " ",
        })

        cursorline = type(item.line) == "number"

        local bufnr = vim.api.nvim_win_get_buf(window)
        has_numbers = vim.bo[bufnr].filetype ~= ""
    end

    local wo = vim.wo[window]
    wo.winhighlight = "Normal:AtlasPreviewWindow"
    wo.cursorline = cursorline
    wo.number = has_numbers
end

---@param instance atlas.Instance
---@param bufnr integer
---@return integer
local function win_open(instance, bufnr)
    local geometry = Geometry.compute_ui_geometry(instance.view.config)
    local window = vim.api.nvim_open_win(bufnr, false, geometry.preview)
    return window
end

---@param instance atlas.Instance
local function update_preview(instance)
    local previewer = instance.view.file_previewer

    if not previewer then
        return
    end

    local selected = instance:get_selected_item()
    if not selected then
        vim.api.nvim_buf_set_lines(previewer.bufnr, 0, -1, false, { "" })
        previewer.filename = nil
        return
    end

    local filename = instance:item_path(selected)

    if filename ~= previewer.filename then
        -- Load a new file.
        local bufnr = buf_create(filename, instance.view.config.files.previewer.filesize_limit)

        vim.api.nvim_win_set_buf(previewer.window, bufnr)

        if vim.api.nvim_buf_is_valid(previewer.bufnr) then
            vim.api.nvim_buf_delete(previewer.bufnr, { force = true })
        end

        previewer.bufnr = bufnr
        previewer.filename = filename
    end

    win_config(previewer.window, selected)
    vim.api.nvim_win_set_cursor(previewer.window, { selected.line or 1, 0 })
end
---@param instance atlas.Instance
function M.toggle(instance)
    if instance.view.file_previewer ~= nil then
        local watcher = instance.view.file_previewer.results_watcher
        if watcher ~= nil then
            vim.api.nvim_del_autocmd(watcher)
        end

        buf_delete(instance.view.file_previewer.bufnr)
        instance.view.file_previewer = nil
        return
    end

    -- Get file contents with :read Ex command.
    local filename = nil
    local selected = instance:get_selected_item()

    if selected then
        filename = instance:item_path(selected)
    end

    local bufnr = buf_create(filename, instance.view.config.files.previewer.filesize_limit)
    local window = win_open(instance, bufnr)

    if selected and selected.line then
        vim.api.nvim_win_set_cursor(window, { selected.line, 0 })
    end

    -- Track changes in the results view.
    local watcher = vim.api.nvim_create_autocmd({ "TextChanged", "CursorMoved" }, {
        group = vim.api.nvim_create_augroup("Atlas/Previewer/Watcher", {}),
        buffer = instance.view.results_buffer,
        callback = function()
            update_preview(instance)
        end,
    })

    win_config(window, selected)

    instance.view.file_previewer = {
        bufnr = bufnr,
        window = window,
        filename = filename,
        results_watcher = watcher,
    }
end

---@param instance atlas.Instance
function M.destroy(instance)
    if instance.view.file_previewer == nil then
        return
    end

    buf_delete(instance.view.file_previewer.bufnr)
end

return M
