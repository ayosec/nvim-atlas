local M = {}

local Buffer = require("string.buffer")
local ItemKind = require("atlas.view").ItemKind

---@class atlas.view.bufdata.Metadata
---@field item_id integer
---@field kind string
---@field level? integer

--- Parse the metadata fragment of a buffer line.
---
--- The expected format is `<KIND><ID>{{{<FOLD> `.
---
---@param line string
---@return atlas.view.bufdata.Metadata|nil
function M.parse_metadata(line)
    local endpos = line:find(" ", 1, true)
    if endpos == nil then
        return nil
    end

    local _, _, kind, item_id, level = line:sub(1, endpos - 1):find("(%a+)(%d+)(.*)")

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

---@alias atlas.view.bufdata.ItemIndex table<integer, atlas.view.Item>

--- Iterator over the entries of a subtree.
---
--- Directories are grouped before other entries.
---
---@generic T: table, K, V
---@param config atlas.Config
---@param tree atlas.view.Tree
---@return fun(table: table<K, V>, index?: integer): boolean, string|integer, atlas.view.Item
local function iter_subtree(config, tree)
    local entries = {} ---@type {key: (string|number)[], item: atlas.view.Item}[]
    local num_entries = 0
    local has_numbers = false

    -- Collect the keys in the subtree.
    for key, item in pairs(tree) do
        table.insert(entries, { key = key, item = item })
        num_entries = num_entries + 1

        if not has_numbers and type(key) == "number" then
            has_numbers = true
        end
    end

    -- Sort the keys.
    table.sort(entries, function(a, b)
        if has_numbers then
            return a.key < b.key
        end

        if config.view.results.directories_first then
            if a.item.kind == ItemKind.Directory and b.item.kind ~= ItemKind.Directory then
                return true
            end

            if a.item.kind ~= ItemKind.Directory and b.item.kind == ItemKind.Directory then
                return false
            end
        end

        return a.key < b.key
    end)

    local i = 0
    return function()
        i = i + 1
        local entry = entries[i]
        if entry then
            return i == num_entries, entry.key, entry.item
        end
    end
end

--- Data to build the contents of the buffer for the view.
---
--- Each line contains a reference to the `items` index, the fold level,
--- and the label.
---
---@class atlas.view.bufdata.BufData
---@field items atlas.view.bufdata.ItemIndex
---@field vartabstop integer[]
---@field lines string[]

---@param config atlas.Config
---@param tree atlas.view.Tree
---@param line_number_width integer
---@param items atlas.view.bufdata.ItemIndex
---@param lines string[]
---@param vartabstop integer[]
---@param indent_prefix string
---@param fold_level integer
---@param buffer string.buffer
local function walk_tree(config, tree, line_number_width, items, lines, vartabstop, indent_prefix, fold_level, buffer)
    local margin_by_depth = config.view.results.margin_by_depth

    -- Indent prefix for non-last children.
    local draw_tree = false
    local tree_hbar = " "
    local subtree_prefix_intermediate = ""
    local subtree_prefix_last = ""

    if type(margin_by_depth) == "number" then
        draw_tree = true

        if fold_level > 1 then
            tree_hbar = string.rep("─", margin_by_depth) .. " "

            local hspaces = string.rep(" ", margin_by_depth) .. " "
            subtree_prefix_intermediate = indent_prefix .. "│" .. hspaces
            subtree_prefix_last = indent_prefix .. hspaces
        end
    end

    for is_last, key, item in iter_subtree(config, tree) do
        table.insert(items, item)

        local has_children = not vim.tbl_isempty(item.children)
        local item_id = #items

        buffer:reset()

        -- Metadata
        buffer:put(item.kind, item_id)

        if has_children then
            buffer:put("{{{", fold_level)
        end

        buffer:put(" ")

        if type(margin_by_depth) == "function" then
            buffer:put(margin_by_depth(fold_level, item))
        end

        -- Filename.
        if type(key) == "string" then
            if draw_tree and fold_level > 1 then
                buffer:put(indent_prefix, is_last and "└" or "├", tree_hbar)
            end
            buffer:put(key)

            -- Directories always has the trailing `/`.
            if item.kind == ItemKind.Directory then
                buffer:put("/")
            end
        else
            if draw_tree then
                buffer:put(indent_prefix, " ")
            end

            if item.line ~= nil then
                local line = tostring(item.line)
                local padding_width = line_number_width - #line
                local padding = padding_width > 0 and string.rep(" ", padding_width) or ""
                buffer:putf("%s@%s", padding, line)
            end
        end

        -- In order to align the matched text we need to compute the width of
        -- the current buffer. Metadata is ignored because it is not visible.
        local line = buffer:tostring()
        local line_width = vim.fn.strwidth(line) + 2

        if vartabstop[1] < line_width then
            vartabstop[1] = line_width
        end

        if item.text ~= nil then
            line = string.format("%s:\t%s", line, vim.trim(item.text))
        end

        -- Final line, include the metadata fragment and the label, with its prefix.
        table.insert(lines, line)

        if has_children then
            walk_tree(
                config,
                item.children,
                line_number_width,
                items,
                lines,
                vartabstop,
                is_last and subtree_prefix_last or subtree_prefix_intermediate,
                fold_level + 1,
                buffer
            )
        end
    end
end

---@param tree atlas.view.Tree
---@param max_line_number integer
---@return atlas.view.bufdata.BufData
function M.render(config, tree, max_line_number)
    local items = {}
    local lines = {}
    local vartabstop = { 1, 8 }

    local line_number_width = #tostring(max_line_number)

    walk_tree(config, tree, line_number_width, items, lines, vartabstop, "", 1, Buffer.new())

    return {
        items = items,
        lines = lines,
        vartabstop = vartabstop,
    }
end

return M
