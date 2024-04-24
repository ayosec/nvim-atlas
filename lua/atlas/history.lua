local M = {}

local viml = vim.api.nvim_eval

---@param var_name string
---@return integer
local function list_len(var_name)
    return viml(string.format([[exists("g:%s") ? len(g:%s) : 0]], var_name, var_name))
end

---@class atlas.impl.History
---@field var_name string
---@field size integer
---@field cursor integer

---@class atlas.impl.History
local History = {}

---@param entry string
function History:add(entry)
    if self.var_name == "" then
        return
    end

    -- Skip the entry if the last one has the same value.
    if viml(string.format("get(g:%s, %d)", self.var_name, -1)) == entry then
        return
    end

    vim.b.__ATLAS_ENTRY = entry
    viml(string.format([[add(g:%s, b:__ATLAS_ENTRY)]], self.var_name))
    vim.b.__ATLAS_ENTRY = nil

    local discard = list_len(self.var_name) - self.size
    if discard > 0 then
        viml(string.format("remove(g:%s, 0, %d)", self.var_name, discard - 1))
    end
end

---@param delta integer
---@return string|nil
function History:go(delta)
    if self.var_name == "" then
        return
    end

    local hist_len = list_len(self.var_name)
    local hist_index = hist_len - self.cursor - delta

    if hist_index < 0 or hist_index >= hist_len then
        return
    end

    self.cursor = self.cursor + delta

    return viml(string.format("get(g:%s, %d)", self.var_name, hist_index))
end

---@param var_name string
---@param size integer
---@return atlas.impl.History
function M.new(var_name, size)
    if size > 0 then
        local expr = string.format([[!exists("g:%s") || type(g:%s) != type([])]], var_name, var_name)
        if viml(expr) == 1 then
            vim.g[var_name] = {}
        end
    else
        var_name = ""
    end

    local h = { var_name = var_name, size = size, cursor = 0 }
    return setmetatable(h, { __index = History })
end

return M
