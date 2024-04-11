local M = {}

--- Adjust a specifier to replace `.` with `\.`, and `*` with `.*`.
---
---@param spec string
---@return string
local function adjust_regex(spec)
    local s, _ = spec:gsub("%.", "\\."):gsub("*", ".*")
    return s
end

---@enum atlas.filter.Kind
M.FilterKind = {
    Simple = 1,
    FileContents = 2,
}

--- Represent a specifier in a filter.
---
---@class atlas.filter.Spec
---@field kind atlas.filter.Kind
---@field negated boolean
---@field value string

---@class atlas.impl.LexerToken
---@field negated boolean
---@field value string

--- Split a filter into lexer tokens.
---
---@param filter string
---@return fun(): atlas.impl.LexerToken|nil
local function lexer(filter)
    local input = filter

    return function()
        input = vim.trim(input)

        if input == "" then
            return nil
        end

        local current
        local negated = false

        if vim.startswith(input, "-") then
            negated = true
            input = input:sub(2)
        end

        if vim.startswith(input, "//") then
            current = input:sub(2)
            input = ""
        else
            current = input:match("%S+")
            input = input:sub(#current + 2)
        end

        return {
            negated = negated,
            value = current,
        }
    end
end

--- Parse a filter and return a list with each specifier.
---
---@param filter string
---@return atlas.filter.Spec[]
function M.parse(filter)
    ---@type atlas.filter.Spec[]
    local specs = {}

    for token in lexer(filter) do
        ---@type atlas.filter.Spec
        local new_spec = {
            kind = M.FilterKind.Simple,
            negated = token.negated,
            value = "",
        }

        if vim.startswith(token.value, "/") then
            new_spec.kind = M.FilterKind.FileContents
            new_spec.value = token.value:sub(2)
        else
            new_spec.value = adjust_regex(token.value)
        end

        table.insert(specs, new_spec)
    end

    return specs
end

return M
