local M = {}

local Geometry = require("atlas.view.geometry")
local Prompt = require("atlas.view.prompt")
local Results = require("atlas.view.results")

---@enum atlas.view.ItemKind
M.ItemKind = {
    Directory = "D",
    File = "F",
    ContentMatch = "M",
}

---@alias atlas.view.Tree table<string|integer, atlas.view.Item>

--- Items in the results view.
---
---@class atlas.view.Item
---@field kind atlas.view.ItemKind
---@field path string
---@field children atlas.view.Tree
---@field line? integer
---@field text? string
---@field highlights? integer[][]

---@class atlas.view.Instance
---@field config atlas.Config
---@field prompt_buffer integer
---@field prompt_window integer
---@field results_buffer integer
---@field results_window integer
---@field file_previewer atlas.impl.FilePreviewer|nil
---@field autocmd_group number

---@param instance atlas.view.Instance
---@param on_leave fun()
---@param on_update fun()
local function register_events(instance, on_leave, on_update)
    -- Recompute window's geometry when Vim itself is resized.
    vim.api.nvim_create_autocmd("VimResized", {
        buffer = instance.prompt_buffer,
        group = instance.autocmd_group,
        nested = true,
        callback = function()
            Geometry.resize_instance(instance)
        end,
    })

    -- Destroy the instance when the cursor leaves the prompt buffer.
    vim.api.nvim_create_autocmd("WinLeave", {
        buffer = instance.prompt_buffer,
        group = instance.autocmd_group,
        callback = function()
            on_leave()
        end,
    })

    -- Track changes on the prompt.
    vim.api.nvim_buf_attach(instance.prompt_buffer, false, {
        on_lines = on_update,
    })
end

--- Create a new instance.
---
---@param config atlas.Config
---@param on_leave fun()
---@param on_update fun()
---@return atlas.view.Instance
function M.create_instance(config, on_leave, on_update)
    local geom = Geometry.compute_ui_geometry(config)

    local prompt_buffer = vim.api.nvim_create_buf(false, true)
    local prompt_window = Prompt.create_window(config, geom, prompt_buffer)

    local results_buffer = vim.api.nvim_create_buf(false, true)
    local results_window = Results.create_window(config, geom, results_buffer)

    for _, bufnr in pairs { prompt_buffer, results_buffer } do
        local bo = vim.bo[bufnr]

        bo.bufhidden = "wipe"
        bo.buftype = "nofile"
    end

    Results.configure_buffer(results_buffer)
    Prompt.configure_buffer(prompt_buffer)

    ---@type atlas.view.Instance
    local instance = {
        config = config,
        prompt_buffer = prompt_buffer,
        prompt_window = prompt_window,
        results_buffer = results_buffer,
        results_window = results_window,
        autocmd_group = vim.api.nvim_create_augroup("AtlasFinder", {}),
    }

    register_events(instance, on_leave, on_update)

    return instance
end

---@param instance atlas.view.Instance
function M.destroy(instance)
    for _, bufnr in ipairs { instance.prompt_buffer, instance.results_buffer } do
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end
end

return M
