local M = {}

local MESSAGES_PREFIX = require("atlas.view.errors").MESSAGES_PREFIX

---@enum atlas.filter.Kind
M.FilterKind = {
    Simple = 1,
    FileContents = 2,
    FileNameWithContents = 3,
}

--- Represent a specifier in a filter.
---
---@class atlas.filter.Filter
---@field source_name string?
---@field source_argument string?
---@field specs atlas.filter.Spec[]

---@class atlas.filter.Spec
---@field kind atlas.filter.Kind
---@field exclude boolean
---@field fixed_string boolean
---@field value string

---@class atlas.impl.LexerToken
---@field exclude boolean
---@field fixed_string boolean
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

        local current = ""
        local exclude = false
        local fixed_string = false

        while input ~= "" do
            if vim.startswith(input, "!") then
                exclude = true
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
            while input ~= "" do
                local fragment = input:match("%S+") or ""
                current = current .. fragment
                input = input:sub(#fragment + 1)

                if input == "" then
                    break
                end

                -- Extend the specifier if it ends in a `\`
                if vim.endswith(fragment, "\\") then
                    current = current:sub(1, -2) .. input:sub(1, 1)
                    input = input:sub(2)
                else
                    input = input:sub(2)
                    break
                end
            end
        end

        -- Remove trailing backslash, except for fixed-strings.
        if vim.endswith(current, "\\") and not fixed_string then
            current = current:sub(1, -2)
        end

        return {
            exclude = exclude,
            fixed_string = fixed_string,
            value = current,
        }
    end
end

--- Parse a filter and return a list with each specifier.
---
---@param filter string
---@return atlas.filter.Filter
function M.parse(filter)
    ---@type atlas.filter.Spec[]
    local specs = {}

    local source_name = nil
    local source_argument = nil

    for token in lexer(filter) do
        ---@type atlas.filter.Spec
        local new_spec = {
            kind = M.FilterKind.Simple,
            exclude = token.exclude,
            fixed_string = token.fixed_string,
            value = "",
        }

        local char_prefix = token.value:sub(1, 1)
        if char_prefix == "/" then
            new_spec.kind = M.FilterKind.FileContents
            new_spec.value = token.value:sub(2)
        elseif char_prefix == "?" then
            new_spec.kind = M.FilterKind.FileNameWithContents
            new_spec.value = token.value:sub(2)
        elseif char_prefix == "@" then
            if source_name ~= nil then
                error(MESSAGES_PREFIX .. "Multiple sources defined")
            end

            source_name = token.value:sub(2)
            local sep = source_name:find(":")
            if sep then
                source_argument = source_name:sub(sep + 1)
                source_name = source_name:sub(1, sep - 1)
            end
        else
            new_spec.value = token.value
        end

        if new_spec.value ~= "" then
            table.insert(specs, new_spec)
        end
    end

    return {
        source_name = source_name,
        source_argument = source_argument,
        specs = specs,
    }
end

return M
