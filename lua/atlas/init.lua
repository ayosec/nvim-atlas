local M = {}

--- @type atlas.Config
M.options = {}

---@return atlas.Config
function M.default_config()
    return require("atlas.config").defaults()
end

---@param opts? atlas.Config
function M.setup(opts)
    local sources = {
        sources = require("atlas.sources").default_sources(),
    }

    M.options = vim.tbl_deep_extend("force", {}, sources, M.default_config(), opts or {})

    require("atlas.highlights").set_defaults()
end

---@class atlas.impl.OriginalEnvironment
---@field cfile string
---@field cword string

---@class atlas.impl.Marks
---@field all boolean
---@field items table<integer, boolean>

---@class atlas.Finder
---@field view atlas.view.Instance
---@field history atlas.impl.History
---@field marks atlas.impl.Marks
---@field items_index atlas.view.bufdata.ItemIndex
---@field default_source? atlas.sources.Response
---@field search_dir string|nil
---@field help atlas.impl.Help
---@field original_environment atlas.impl.OriginalEnvironment
---@field git_stats nil|atlas.impl.GitStats
---@field state table<string, any>

---@class atlas.Finder
local FinderMeta = {}

--- Delete the buffers used by this instance.
---
--- If there is any running pipeline, it will be terminated.
---@param history_add boolean
function FinderMeta:destroy(history_add)
    if history_add then
        self.history:add(vim.trim(self:get_prompt()))
    end

    -- Ensure Normal mode on exit.
    if vim.fn.mode() ~= "n" then
        local k = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
        vim.api.nvim_feedkeys(k, "n", false)
    end

    require("atlas.view").destroy(self.view)
    require("atlas.preview").destroy(self)
    require("atlas.help").destroy(self)

    require("atlas.updater").interrupt(self)
end

--- Open the files of current selection.
---
--- If there is any running pipeline, it will be terminated.
---@param use_tabs boolean
function FinderMeta:accept(use_tabs)
    local _, id = self:get_selected_item()

    if id then
        self.marks.items[id] = true
    end

    local paths = {}
    local line_jumps = {}

    for item_id, marked in pairs(self.marks.items) do
        local item_data = self.items_index[item_id]
        if marked and item_data then
            local item = item_data.item
            local path = self:item_path(item)
            table.insert(paths, vim.fn.fnameescape(path))

            if item.line then
                line_jumps[path] = item.line
            end
        end
    end

    self:destroy(true)

    if #paths > 0 then
        local mods = {}
        if use_tabs or #paths > 1 then
            mods.tab = vim.fn.tabpagenr()
        end

        vim.cmd.drop {
            args = paths,
            mods = mods,
        }

        -- Update the first window for the selected files if the
        -- selected item has a line number
        for path, linenum in pairs(line_jumps) do
            local window = vim.fn.win_findbuf(vim.fn.bufnr(path))
            if #window > 0 then
                vim.api.nvim_win_set_cursor(window[1], { linenum, 0 })
            end
        end
    end
end

---@return string
function FinderMeta:get_prompt()
    local lines = vim.api.nvim_buf_get_lines(self.view.prompt_buffer, 0, -1, false)
    return table.concat(lines, "\n")
end

---@param prompt string
function FinderMeta:set_prompt(prompt)
    local lines = vim.split(prompt, "\n", { trimempty = true })
    vim.api.nvim_buf_set_lines(self.view.prompt_buffer, 0, -1, false, lines)

    -- Put cursor at the end of the prompt.
    vim.schedule(function()
        local rows = #lines
        if rows > 0 then
            vim.api.nvim_win_set_cursor(self.view.prompt_window, { rows, #lines[rows] + 1 })
        end
    end)
end

--- Return the item in a specific line.
---@param row integer
---@return nil|atlas.view.Item
---@return nil|integer
function FinderMeta:get_item(row)
    local line = vim.api.nvim_buf_get_lines(self.view.results_buffer, row - 1, row, false)
    if not line or not line[1] then
        return
    end

    local item_id = tonumber(string.match(line[1], "^(%d+)"))
    if item_id then
        local item = self.items_index[item_id].item
        if item then
            return item, item_id
        end
    end
end

--- Return the item in the row of the current selection.
---@return nil|atlas.view.Item
---@return nil|integer
function FinderMeta:get_selected_item()
    local row = vim.api.nvim_win_get_cursor(self.view.results_window)[1]
    return self:get_item(row)
end

--- Path for an item, relative to the current directory.
---
---@param item atlas.view.Item
---@return string
function FinderMeta:item_path(item)
    local path = string.format("%s/%s", self.search_dir, item.path)
    return vim.fn.fnamemodify(vim.fn.simplify(path), ":.")
end

---@param bufname string
---@param finder atlas.Finder
local function preselect_current_buffer(bufname, finder)
    if bufname == "" then
        return
    end

    bufname = vim.fn.fnamemodify(bufname, ":.")

    -- On first update, try to put the cursor on the current buffer,
    -- only if it is in the first 100 rows.

    vim.api.nvim_create_autocmd({ "TextChanged" }, {
        group = vim.api.nvim_create_augroup("Atlas/Results/Preselect", {}),
        once = true,
        buffer = finder.view.results_buffer,
        callback = function()
            for row = 1, 100 do
                local item = finder:get_item(row)
                if item == nil then
                    break
                end

                local path = finder:item_path(item)

                if path == bufname then
                    vim.schedule(function()
                        vim.api.nvim_win_set_cursor(finder.view.results_window, { row, 0 })
                    end)

                    break
                end
            end
        end,
    })
end

---@class atlas.FindOptions
---@field config? atlas.Config
---@field initial_prompt? string
---@field default_source? atlas.sources.Response

---@param options? atlas.FindOptions
---@return atlas.Finder
function M.find(options)
    if options == nil then
        options = {}
    end

    local original_bufname = vim.api.nvim_buf_get_name(0)

    ---@type atlas.impl.OriginalEnvironment
    local original_environment = {
        cword = vim.fn.expand("<cword>"),
        cfile = vim.fn.expand("<cfile>"),
    }

    ---@type atlas.Config
    local config = vim.tbl_deep_extend("force", {}, M.options, options.config or {})

    local finder = {
        history = require("atlas.history").new_default(config.search.history_size),
        marks = { all = false, items = {} },
        items_index = {},
        default_source = options.default_source,
        help = { keymap = {} },
        original_environment = original_environment,
        state = {},
    }

    local on_leave = function()
        finder:destroy(false)
    end

    local on_update = function()
        require("atlas.updater").update(finder)
    end

    finder.view = require("atlas.view").create_instance(config, on_leave, on_update)
    setmetatable(finder, { __index = FinderMeta })

    preselect_current_buffer(original_bufname, finder)

    require("atlas.view.prompt").initialize_input(config, finder.view, options.initial_prompt, finder.history)

    require("atlas.keymap").apply_keymap(finder, finder.view.prompt_buffer, config.mappings)

    -- Store the instance as a buffer variable, so it can be accessed in handlers.
    for _, bufnr in ipairs { finder.view.results_buffer, finder.view.prompt_buffer } do
        vim.b[bufnr].AtlasFinder = function()
            return finder
        end
    end

    -- Collect git stats.
    if config.files.git.enabled then
        require("atlas.git").stats(
            config.files.search_dir(),
            config.programs.git,
            config.files.git.diff_arguments,
            function(code, result)
                if code == 0 then
                    require("atlas.updater").set_git_stats(finder, result)
                end
            end
        )
    end

    on_update()

    return finder
end

return M
