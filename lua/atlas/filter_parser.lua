local M = {}

--- Adjust a specifier to replace `.` with `\.`, and `*` with `.*`.
---
---@param spec string
---@return string
local function adjust_regex(spec)
    local s, _ = spec:gsub("%.", "\\."):gsub("*", ".*")
    return s
end

---@enum kind
M.FilterKind = {
    Simple = 1,
    FileContents = 2,
}

--- Represent a specifier in a filter.
---
---@class FilterSpec
---@field kind kind
---@field negated boolean
---@field value string

--- Parse a filter and return a list with each specifier.
---
---@param filter string
---@return FilterSpec[]
function M.parse(filter)
    ---@type FilterSpec[]
    local specs = {}

    for spec in filter:gmatch("%S+") do
        ---@type FilterSpec
        local new_spec = {
            kind = M.FilterKind.Simple,
            negated = false,
            value = "",
        }

        if vim.startswith(spec, "-") then
            new_spec.negated = true
            spec = spec:sub(2)
        end

        if vim.startswith(spec, "/") then
            new_spec.kind = M.FilterKind.FileContents
            new_spec.value = spec:sub(2)
        else
            new_spec.value = adjust_regex(spec)
        end

        table.insert(specs, new_spec)
    end

    return specs
end

return M
