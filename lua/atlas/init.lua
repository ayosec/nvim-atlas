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
    require("atlas.view").destroy(self.view)
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

    return instance
end

return M
