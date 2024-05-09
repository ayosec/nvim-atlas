local M = {}

local FilterKind = require("atlas.filter").FilterKind

---@param filter atlas.filter.Filter
---@param source? atlas.sources.Response
---@return nil|atlas.searchprogram.ProgramOutput
function M.try_search(filter, source)
    if source == nil or source.items == nil then
        return nil
    end

    -- Compile the regexes from the specs
    local patterns = {}

    for _, spec in ipairs(filter.specs) do
        local exclude = spec.exclude
        local regex = spec.value

        if spec.fixed_string then
            regex = "\\V" .. vim.fn.escape(regex, "\\")
        else
            regex = "\\v" .. regex
        end

        local field_text = true
        local regex_comp = vim.regex(regex) ---@type any

        if spec.kind == FilterKind.Simple then
            field_text = false
        end

        ---@param item atlas.searchprogram.ResultItem
        local pattern = function(item)
            local s = field_text and item.text or item.file or ""
            local matched = regex_comp:match_str(s) ~= nil

            if exclude then
                return not matched
            else
                return matched
            end
        end

        table.insert(patterns, pattern)
    end

    local items = {}
    local max_line_number = 0

    for _, item in ipairs(source.items) do
        local line = item.line
        if line and line > max_line_number then
            max_line_number = line
        end

        local matched = true
        for _, pattern in ipairs(patterns) do
            if not pattern(item) then
                matched = false
                break
            end
        end

        if matched then
            table.insert(items, item)
        end
    end

    ---@type atlas.searchprogram.ProgramOutput
    return {
        items = items,
        max_line_number = max_line_number,
        search_dir = source.search_dir or ".",
    }
end

return M
