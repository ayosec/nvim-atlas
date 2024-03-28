local M = {}

---@enum kind
M.FilterKind = {
    Simple = 1,
}

---@class FilterSpec
---@field kind kind
---@field value string

---Parse a filter and return a list with each specifier.
---@param filter string
---@return FilterSpec[]
M.parse = function(filter)
    local specs = {}

    for spec in string.gmatch(filter, "%S+") do
        table.insert(specs, {
            kind = M.FilterKind.Simple,
            value = spec,
        })
    end

    return specs
end

return M
