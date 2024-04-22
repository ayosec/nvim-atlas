local M = {}

M.namespace = vim.api.nvim_create_namespace("Atlas")

--- @type atlas.Config
M.options = {}

---@return atlas.Config
function M.default_config()
    return require("atlas.config").defaults()
end

---@param opts? atlas.Config
function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", {}, M.default_config(), opts or {})
end

---@class atlas.Instance
---@field view atlas.view.Instance
---@field items_index atlas.view.bufdata.ItemIndex
---@field state table<string, any>

---@class atlas.Instance
local InstanceMeta = {}

--- Delete the buffers used by this instance.
---
--- If there is any running pipeline, it will be terminated.
function InstanceMeta:destroy()
    -- Ensure Normal mode on exit.
    if vim.fn.mode() ~= "n" then
        local k = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
        vim.api.nvim_feedkeys(k, "n", false)
    end

    require("atlas.view").destroy(self.view)
end

--- Open the files of current selection.
---
--- If there is any running pipeline, it will be terminated.
function InstanceMeta:accept()
    local selected = self:get_selected_item()
    self:destroy()

    if selected then
        vim.cmd.drop {
            args = { selected.path },
            mods = { tab = vim.fn.tabpagenr() },
        }
    end
end

--- Return the item in the row of the current selection.
---@return nil|atlas.view.Item
function InstanceMeta:get_selected_item()
    local row = vim.api.nvim_win_get_cursor(self.view.results_window)[1]

    local line = vim.api.nvim_buf_get_lines(self.view.results_buffer, row - 1, row, false)
    if not line then
        return
    end

    local metadata = require("atlas.view.bufdata").parse_metadata(line[1])
    if metadata then
        return self.items_index[metadata.item_id]
    end
end

---@class atlas.OpenOptions
---@field config? atlas.Config
---@field initial_prompt? string

---@param options? atlas.OpenOptions
---@return atlas.Instance
function M.open(options)
    if options == nil then
        options = {}
    end

    local config = options.config or vim.deepcopy(M.options)

    local instance = {}
    setmetatable(instance, { __index = InstanceMeta })

    local on_leave = function()
        instance:destroy()
    end

    local on_update = function()
        require("atlas.updater").update(instance)
    end

    instance.view = require("atlas.view").create_instance(config, on_leave, on_update)
    instance.items_index = {}
    instance.state = {}

    require("atlas.view.prompt").initialize_input(config, instance.view, options.initial_prompt)

    require("atlas.keymap").apply_keymap(instance, instance.view.prompt_buffer, config.mappings)

    return instance
end

return M
