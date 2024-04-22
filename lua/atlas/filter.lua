local M = {}

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
---@field fixed_string boolean
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
        local fixed_string = false

        while input ~= "" do
            if vim.startswith(input, "-") then
                negated = true
            elseif vim.startswith(input, "=") then
                fixed_string = true
            else
                break
            end

            input = input:sub(2)
        end

        if vim.startswith(input, "//") then
            current = input:sub(2)
            input = ""
        else
            current = input:match("%S+") or ""
            input = input:sub(#current + 2)
        end

        return {
            negated = negated,
            fixed_string = fixed_string,
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
            fixed_string = token.fixed_string,
            value = "",
        }

        if vim.startswith(token.value, "/") then
            new_spec.kind = M.FilterKind.FileContents
            new_spec.value = token.value:sub(2)
        else
            new_spec.value = token.value
        end

        if new_spec.value ~= "" then
            table.insert(specs, new_spec)
        end
    end

    return specs
end

return M
