local M = {}

--- Add or remove fragments inside a text.
---
--- If `fragment` is already in `text`, it returns a copy of `text` with no
--- occurrences of `fragment`. In other case, it prepends `fragment` to `text`.
---
---@param text string
---@param fragment string
function M.toggle(text, fragment)
    local updated = nil
    local offset = 1

    while offset < #text do
        local start, ends = text:find(fragment, offset, true)

        if start == nil then
            if updated == nil then
                -- `fragment` is not in `text`
                return string.format("%s %s", fragment, text)
            else
                return updated .. text:sub(offset)
            end
        end

        if start > offset then
            updated = (updated or "") .. text:sub(offset, start - 1)
        else
            updated = ""
        end

        local next_offset = text:find("%S", ends + 1, false)
        if next_offset then
            offset = next_offset
        else
            return updated
        end
    end
end

return M
