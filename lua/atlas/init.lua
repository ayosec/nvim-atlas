local M = {}

M.namespace = vim.api.nvim_create_namespace("atlas")

function M.defaults()
    ---@class atlas.Config
    local defaults = {
        user_command = "Atlas",

        programs = {
            ripgrep = "rg",
            xargs = "xargs",
        },

        files = {
            exclude_always = { ".git" },

            hidden = true,

            --- Return the root directory for the search commands.
            ---
            ---@return string|nil
            search_dir = function() end,
        },

        view = {
            max_lines = 30,
        },
    }

    return defaults
end

--- @type atlas.Config
M.options = {}

---@param opts? atlas.Config
function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", {}, M.defaults(), opts or {})
end

return M
