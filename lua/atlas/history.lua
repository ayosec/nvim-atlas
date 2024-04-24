local M = {}

---@type string[]
local ATLAS_HISTORY = {}

local init_from_global_var = false

local islist = vim.islist or vim.tbl_islist

---@class atlas.impl.History
---@field storage string[]
---@field size integer
---@field cursor integer

---@class atlas.impl.History
local History = {}

---@param entry string
function History:add(entry)
    if self.size < 1 then
        return
    end

    -- Skip the entry if the last one has the same value.
    if #self.storage > 0 and self.storage[#self.storage] == entry then
        return
    end

    table.insert(self.storage, entry)

    while #self.storage > self.size do
        table.remove(self.storage, 1)
    end
end

---@param delta integer
---@return string|nil
function History:go(delta)
    if self.size < 1 then
        return
    end

    local hist_len = #self.storage
    local hist_index = hist_len - self.cursor - delta

    if hist_index < 0 or hist_index >= hist_len then
        return
    end

    self.cursor = self.cursor + delta

    return self.storage[hist_index + 1]
end

---@param storage string[]
---@param size integer
---@return atlas.impl.History
function M.new(storage, size)
    local h = { storage = storage, size = size, cursor = 0 }
    return setmetatable(h, { __index = History })
end

---@param size integer
---@return atlas.impl.History
function M.new_default(size)
    if not init_from_global_var then
        -- Save history in a global variable before exiting Nvim, only
        -- if global variables are written to the ShaDa file.
        vim.api.nvim_create_autocmd("VimLeavePre", {
            group = vim.api.nvim_create_augroup("Atlas/History", {}),
            desc = "Storage Atlas history in a global variable",
            pattern = "*",
            callback = function()
                if vim.tbl_contains(vim.opt.shada:get(), "!") then
                    vim.g.ATLAS_HISTORY = ATLAS_HISTORY
                end
            end,
        })

        -- Load the history entries from a previous session, only
        -- if it is a list.
        local prev = vim.g.ATLAS_HISTORY
        if prev and islist(prev) then
            ATLAS_HISTORY = vim.tbl_map(tostring, prev)
        end

        init_from_global_var = true
    end

    local h = { storage = ATLAS_HISTORY, size = size, cursor = 0 }
    return setmetatable(h, { __index = History })
end

return M
