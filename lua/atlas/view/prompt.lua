local M = {}

---@param keys string
local function type_keys(keys)
    local k = vim.api.nvim_replace_termcodes(keys, true, false, true)
    vim.api.nvim_feedkeys(k, "n", false)
end

---@param instance atlas.view.Instance
local function configure_select_mode(instance)
    -- When the buffer enters in SELECT, the event CursorMoved is listened
    -- to detect if the users moves the cursor instead of writing something
    -- to replace the existing input.

    local mode_listener = -1

    mode_listener = vim.api.nvim_create_autocmd("ModeChanged", {
        group = instance.autocmd_group,
        buffer = instance.prompt_buffer,
        callback = function(event)
            if not event.match:match(":s") then
                return
            end

            vim.api.nvim_del_autocmd(mode_listener)

            vim.api.nvim_create_autocmd("CursorMoved", {
                group = instance.autocmd_group,
                buffer = instance.prompt_buffer,
                once = true,
                callback = function()
                    type_keys("<Esc>i")
                end,
            })
        end,
    })
end

local function prompt_omnifunc(find_sart, base)
    if find_sart == 1 then
        ---@diagnostic disable-next-line:param-type-mismatch,undefined-field
        local line = vim.fn.getline("."):sub(1, vim.fn.col(".") - 1)
        local last_word = line:find("%S+$")
        return (last_word or 1) - 1
    end

    if base:sub(1, 1) ~= "@" then
        return {}
    end

    ---@type atlas.Finder
    ---@diagnostic disable-next-line:undefined-field
    local finder = vim.b.AtlasFinder()

    ---@type { word: string, menu: string }[]
    local completions = {}

    base = base:lower()

    for names, source in pairs(finder.view.config.sources) do
        if type(names) == "string" then
            names = { names }
        end

        for _, name in pairs(names) do
            name = "@" .. name
            if vim.startswith(name:lower(), base) then
                table.insert(completions, { word = name, menu = source.help })
            end
        end
    end

    table.sort(completions, function(a, b)
        return a.word:lower() < b.word:lower()
    end)

    return completions
end

--- Configure the options and the syntax for the prompt buffer.
---
---@param bufnr integer
function M.configure_buffer(bufnr)
    local bo = vim.bo[bufnr]
    bo.filetype = "AtlasPrompt"
    bo.omnifunc = "v:lua.vim.b.AtlasOmnifunc"

    vim.b[bufnr].AtlasOmnifunc = prompt_omnifunc

    local function fragment(group, prefix)
        vim.cmd.syntax(
            "region",
            group,
            string.format([[start=/\M%s/]], vim.fn.escape(prefix, "/")),
            [[skip=/\\\s/]],
            [[end=/\s/]]
        )
    end

    vim.api.nvim_buf_call(bufnr, function()
        -- Define first to set lowest priority.
        fragment("AtlasPromptItemOther", "\\S")

        vim.cmd.syntax("match", "AtlasPromptItemExclude", [[=\!=]])
        vim.cmd.syntax("match", "AtlasPromptItemFixedString", [[/=/]])

        fragment("AtlasPromptItemRegex", "/")
        fragment("AtlasPromptItemQuestionRegex", "?")
        fragment("AtlasPromptItemSource", "@")

        vim.cmd.syntax("match", "AtlasPromptItemRegex", [[=//.\+=]])
    end)
end

---@param config atlas.Config
---@param geometry atlas.view.geometry.Geometry
---@param bufnr integer
---@return integer
function M.create_window(config, geometry, bufnr)
    local cfg = config.view.prompt

    local window = vim.api.nvim_open_win(bufnr, true, geometry.prompt)
    local wo = vim.wo[window]

    wo.winhighlight = "Normal:AtlasPromptWindow"
    wo.wrap = false

    ---@diagnostic disable-next-line:inject-field
    wo.statuscolumn = "%#AtlasPromptPrefix#" .. cfg.prefix

    return window
end

---@param config atlas.Config
---@param instance atlas.view.Instance
---@param initial_value string|nil
---@param history atlas.impl.History
function M.initialize_input(config, instance, initial_value, history)
    vim.api.nvim_set_current_win(instance.prompt_window)

    -- Use the last entry of the history if there is no `initial_value`
    if initial_value == nil then
        initial_value = history:go(1)
    end

    -- No value to initialize the prompt. Just start Insert mode.
    if initial_value == nil or initial_value == "" then
        vim.cmd.startinsert()
        return
    end

    if config.view.prompt.select_initial_value then
        -- Add two spaces after the value, so we can use both <End> and <Right>
        -- to exit SELECT, and start writing at the end.
        initial_value = initial_value:gsub("%s+$", "") .. "  "
    end

    vim.api.nvim_buf_set_lines(instance.prompt_buffer, 0, -1, false, { initial_value })

    -- Configure SELECT.
    if not config.view.prompt.select_initial_value then
        return
    end

    -- SELECT the line from beginning until the last non-blank.
    type_keys("gg0vG$hh<C-g>")

    -- Exit SELECT if cursor is moved.
    configure_select_mode(instance)
end

return M
