local utils = {}

local islist = vim.islist or vim.tbl_islist

--- Check if all items from `items` are present in `target`
---
---@param target any[]
---@param items any[]
function utils.assert_list_contains(target, items)
    if not islist(target) then
        error("Expected a list, found " .. vim.inspect(target))
    end

    for _, item in ipairs(items) do
        if not vim.tbl_contains(target, item) then
            error("Missing " .. vim.inspect(item) .. " in " .. vim.inspect(target))
        end
    end
end

return utils
