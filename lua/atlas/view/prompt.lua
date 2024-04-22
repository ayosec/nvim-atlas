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

    local mode_listener = nil

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

local function default_highlights()
    local default_links = {
        AtlasPromptItemNegate = "Operator",
        AtlasPromptItemRegex = "String",
        AtlasPromptItemSource = "Identifier",
        AtlasPromptPrefix = "Identifier",
        AtlasPromptWindow = "Normal",
    }

    for from, to in pairs(default_links) do
        if vim.fn.hlexists(from) == 0 then
            vim.api.nvim_set_hl(0, from, { link = to })
        end
    end
end

--- Configure the options and the syntax for the prompt buffer.
---
---@param bufnr integer
function M.configure_buffer(bufnr)
    vim.api.nvim_buf_call(bufnr, function()
        default_highlights()

        -- Define first to set lowest priority.
        vim.cmd.syntax("match", "AtlasPromptItemOther", [[/\S\+/]])

        vim.cmd.syntax("match", "AtlasPromptItemNegate", [[/-/]])

        vim.cmd.syntax("match", "AtlasPromptItemRegex", [[=/\S\+=]])
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

    wo.statuscolumn = "%#AtlasPromptPrefix#" .. cfg.prefix
    wo.winhighlight = "Normal:AtlasPromptWindow"
    wo.wrap = false

    return window
end

---@param config atlas.Config
---@param instance atlas.view.Instance
---@param initial_value string|nil
function M.initialize_input(config, instance, initial_value)
    vim.api.nvim_set_current_win(instance.prompt_window)

    if initial_value == nil or instance == "" then
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
    type_keys("0v$bel<C-g>")

    -- Exit SELECT if cursor is moved.
    configure_select_mode(instance)
end

return M
