local M = {}

local ItemKind = require("atlas.view").ItemKind

---@class atlas.view.bufdata.Metadata
---@field item_id integer
---@field kind string
---@field level? integer

--- Parse the metadata fragment of a buffer line.
---
--- The expected format is `##KIND/ID/{{{FOLD##`.
---
---@param line string
---@return atlas.view.bufdata.Metadata|nil
function M.parse_metadata(line)
    if not vim.startswith(line, "##") then
        return nil
    end

    local startpos = 3
    local endpos = line:find("##", startpos, true)

    if endpos == nil then
        return nil
    end

    local inner = line:sub(startpos, endpos - 1)
    local kind, item_id, level = unpack(vim.split(inner, "/"))

    item_id = tonumber(item_id)

    if #level > 0 then
        level = tonumber(level:gsub("{+", ""), 10)
    else
        level = nil
    end

    return {
        item_id = item_id,
        kind = kind,
        level = level,
    }
end

--- Data to build the contents of the buffer for the view.
---
--- Each line contains a reference to the `items` index, the fold level,
--- and the label.
---
---@class atlas.view.bufdata.BufData
---@field items table<integer, atlas.view.Item>
---@field lines string[]

---@param config atlas.Config
---@param tree atlas.view.Tree
---@param items table<integer, atlas.view.Item>
---@param lines string[]
---@param fold_level integer
local function walk_tree(config, tree, items, lines, fold_level)
    local level_margin_fn = config.view.level_margin_fn

    for key, item in vim.spairs(tree) do
        table.insert(items, item)

        local has_children = not vim.tbl_isempty(item.children)
        local item_id = #items
        local label = item.text or key

        -- Directories always has the trailing `/`.
        if item.kind == ItemKind.Directory then
            label = label .. "/"
        end

        -- Prefix to put before the item lab.
        local label_prefix = " "

        if level_margin_fn == nil then
            local depth = fold_level - 1
            if depth > 0 then
                label_prefix = label_prefix .. string.rep("   ", depth)
            end
        else
            label_prefix = level_margin_fn(fold_level, item)
        end

        if item.line ~= nil then
            label_prefix = label_prefix .. "@" .. item.line .. ": "
        end

        local fold_marker = ""
        if has_children then
            fold_marker = "{{{" .. fold_level
        end

        -- Final line, include the metadata fragment and the label, with its prefix.
        local line = string.format("##%s/%d/%s##%s%s", item.kind, item_id, fold_marker, label_prefix, label)
        table.insert(lines, line)

        if has_children then
            walk_tree(config, item.children, items, lines, fold_level + 1)
        end
    end
end

---@param tree atlas.view.Tree
---@return atlas.view.bufdata.BufData
function M.render(config, tree)
    local items = {}
    local lines = {}

    walk_tree(config, tree, items, lines, 1)

    return {
        items = items,
        lines = lines,
    }
end

return M
