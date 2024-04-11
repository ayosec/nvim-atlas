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
            --- Function to return a string for the left margin of a subtree.
            --- It receives the depth level (1-based), and is called for each
            --- file.
            ---
            --- If `nil`, the left margin is filled with three spaces for
            --- each level after the top.
            ---
            ---@type nil|fun(level: integer, item: atlas.view.Item): string
            level_margin_fn = nil,
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
