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

--- Return an iterator to get the unindented lines of a `[[ ]]` string.
---
---@param lines string
---@return fun(): string
function utils.lines(lines)
    local it = vim.gsplit(lines, "\n")
    return function()
        local line = it()
        if line then
            return vim.trim(line):gsub("\\t", "\t")
        end

        error("No more lines")
    end
end

return utils
