local M = {}

---@alias atlas.KeyMapHandler fun(instance: atlas.Instance): any
---@alias atlas.KeyMap table<string, false|atlas.KeyMapHandler>
---@alias atlas.KeyMappings table<string[]|string, atlas.KeyMap>

function M.defaults()
    ---@class atlas.Config
    local defaults = {
        --- Name of the user command to open an Atlas instance.
        ---
        --- If `nil`, no command will be created.
        ---
        ---@type string|nil
        user_command = "Atlas",

        programs = {
            --- Path to execute the `rg` program.
            ---@type string
            ripgrep = vim.fn.exepath("rg"),

            --- Path to execute the `xargs` program.
            ---@type string
            xargs = vim.fn.exepath("xargs"),
        },

        search = {
            --- Maximum number of results in a single search.
            ---@type integer
            max_results = 100,

            --- Time, in milliseconds, after the last change in the prompt to
            --- run the search.
            ---@type integer
            update_wait_time = 50,

            --- Determine if search patterns are case-sensitive (`true`) or
            --- case-insensitive (`false`).
            ---
            --- If it is `"smart"`, the patterns are case-insensitive if all letters
            --- are lowercase. See the documentation of the `--smart-case` argument
            --- in ripgrep for more details.
            ---
            ---@type boolean|"smart"
            case_sensitivity = "smart",

            --- Number of entries to keep in the input history.
            ---
            --- History is stored in a global variable, so it can be restored
            --- in new Neovim sessions if the `shada` option contains the `!`
            --- character. See `:help shada-!` for more details.
            ---
            --- If `0`, history will be disabled.
            history_size = 20,
        },

        files = {
            --- List of patterns to be excluded from the search. Each item in
            --- this list is added to the ripgrep command as `--glob !$ITEM`.
            ---
            ---@type string[]
            exclude_always = { ".git" },

            --- Include hidden files in the results.
            ---@type boolean
            hidden = true,

            --- Return the root directory for the search commands.
            ---
            ---@return string|nil
            search_dir = function() end,
        },

        --- Mappings available in the prompt view.
        ---
        --- Keys are the mode to define the mapping (`n` for Normal, `i` for
        --- Insert, etc). In each mode, the key is the sequence to trigger the
        --- mapping, and the value is a function with a single `atlas.Instance`
        --- argument.
        ---
        --- ```lua
        ---   mappings = {
        ---       i = {
        ---           ["<C-o>"] = function(instance) ... end
        ---       }
        ---   }
        --- ```
        ---
        --- The module `atlas.actions` provides multiple functions to build the
        --- handlers.
        ---
        --- ```lua
        ---   mappings = {
        ---       i = {
        ---           ["<C-o>"] = require("atlas.actions").toggle_text("example")
        ---       }
        ---   }
        --- ```
        ---
        --- Default mappings can be disabled setting the sequence to `false`:
        ---
        --- ```lua
        ---   mappings = {
        ---       n = {
        ---           ["<C-f>"] = false,
        ---       }
        ---   }
        --- ```
        ---
        ---@type atlas.KeyMappings
        mappings = {},

        view = {
            --- Height of the view.
            ---
            --- If the value is a string with the format `N%`, the height is
            --- computed as the N% of the editor window.
            ---
            --- If it is an integer, the height will be fixed.
            ---
            ---@type string|integer
            height = "40%",

            results = {
                --- If `true`, directories are always before files.
                ---@type boolean
                directories_first = true,

                --- String to mark the current selection, or `nil` to disable
                --- the mark.
                ---@type string|nil
                selection_mark = "> ",

                --- Highlight group for the mark
                ---@type string
                selection_mark_highlight = "Normal",

                --- Function to return a string for the left margin of a subtree.
                --- It receives the depth level (1-based), and is called for each
                --- file.
                ---
                --- If the value is an integer, the left margin is used to draw a
                --- tree with box-drawing Unicode characters, where each filename
                --- is preceded by the `─` character repeated the number of times
                --- specified by this setting.
                ---
                ---@type integer|fun(level: integer, item: atlas.view.Item): string
                margin_by_depth = 2,
            },

            prompt = {
                --- If `true`, the prompt is started in Select mode.
                ---
                ---@type boolean
                select_initial_value = true,

                --- String to put before the prompt.
                ---
                ---@type string
                prefix = "> ",

                --- Character to draw the border over the prompt. If `nil`, the border
                --- is turned off.
                ---
                ---@type string|nil
                border_char = "▁",
            },
        },
    }

    return defaults
end

return M
