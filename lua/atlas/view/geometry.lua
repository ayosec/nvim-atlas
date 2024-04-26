local M = {}

---@class atlas.view.geometry.Geometry
---@field preview atlas.view.geometry.WindowOptions
---@field prompt atlas.view.geometry.WindowOptions
---@field results atlas.view.geometry.WindowOptions

---@class atlas.view.geometry.WindowOptions
---@field col integer
---@field row integer
---@field width integer
---@field height integer
---@field relative string
---@field style string

---@param config atlas.Config
---@return atlas.view.geometry.Geometry
function M.compute_ui_geometry(config)
    local ui = vim.api.nvim_list_uis()[1]
    local height = config.view.height

    -- If we don't have an UI (for example, on headless mode),
    -- defaults to a 100x50 grid.
    if ui == nil then
        ui = {
            width = 100,
            height = 50,
        }
    end

    local prompt_border = nil
    local prompt_border_height = 0
    if config.view.prompt.border_char ~= nil then
        prompt_border_height = 1
        prompt_border = { "", config.view.prompt.border_char, "", "", "", "", "", "" }
    end

    local lines
    if type(height) == "string" and height:sub(-1) == "%" then
        local perc = tonumber(height:sub(1, -2), 10)
        lines = math.floor(perc * ui.height / 100)
    else
        local l = tonumber(height)
        if l == nil then
            error("Invalid value for atlas.view.height: " .. vim.inspect(height))
        end

        lines = l
    end

    lines = math.max(2 + prompt_border_height, lines)
    local prompt_row = ui.height - lines - 2

    local preview_win = config.files.previewer.window
    local preview_border_rows = preview_win.border == "none" and 0 or 2

    return {
        preview = {
            col = preview_win.padding,
            row = preview_win.padding,
            width = ui.width - preview_win.padding * 2,
            height = prompt_row - preview_win.padding * 2 - preview_border_rows,
            relative = "editor",
            style = "minimal",
            border = preview_win.border,
        },
        prompt = {
            col = 0,
            row = prompt_row - prompt_border_height,
            width = ui.width,
            height = 1,
            relative = "editor",
            style = "minimal",
            border = prompt_border,
        },
        results = {
            col = 0,
            row = prompt_row + 1,
            width = ui.width,
            height = lines - 1,
            relative = "editor",
            style = "minimal",
        },
    }
end

---@param instance atlas.view.Instance
function M.resize_instance(instance)
    local resized = M.compute_ui_geometry(instance.config)

    -- Window options to restore after updating the positions.
    --
    -- Windows are created with `style = "minimal"`, and it seems that
    -- `nvim_win_set_config` will reset these options even if `style` is
    -- not added to the arguments.
    local restore_opts = { "cursorline", "number", "statuscolumn" }

    local windows = {
        { instance.prompt_window, resized.prompt },
        { instance.results_window, resized.results },
        { instance.file_previewer and instance.file_previewer.window, resized.preview },
    }

    for _, win in ipairs(windows) do
        if win[1] then
            local wo = vim.wo[win[1]]

            -- Save options.
            local opts = {}
            for _, prop_name in ipairs(restore_opts) do
                opts[prop_name] = wo[prop_name]
            end

            vim.api.nvim_win_set_config(win[1], win[2])

            -- Restore options.
            for k, v in pairs(opts) do
                wo[k] = v
            end
        end
    end
end

return M
