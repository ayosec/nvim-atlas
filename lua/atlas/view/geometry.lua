local M = {}

---@class atlas.view.geometry.Geometry
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

    return {
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

    vim.api.nvim_win_set_config(instance.prompt_window, resized.prompt)
    vim.api.nvim_win_set_config(instance.results_window, resized.results)
end

return M
