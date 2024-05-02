local M = {}

local ItemKind = require("atlas.view").ItemKind

M.NS_MARKED_FILES = vim.api.nvim_create_namespace("Atlas/Results/MarkedFiles")

---@class atlas.view.bufdata.ItemData
---@field id integer
---@field item atlas.view.Item
---@field row_text table<string, atlas.view.bufdata.Column>

---@alias atlas.view.bufdata.Column string[][]

---@alias atlas.view.bufdata.ItemIndex table<integer, atlas.view.bufdata.ItemData>

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

---@param item atlas.view.Item
---@return atlas.view.bufdata.Column
local function render_text_column(item)
    local text = item.text
    local highlights = item.highlights

    if not text then
        return {}
    end

    if highlights == nil or #highlights == 0 then
        return {
            {
                vim.trim(text),
                "AtlasResultsMatchText",
            },
        }
    end

    -- Compute how many spaces are at the beginning. Offsets must
    -- be adjusted if we trim the string.

    local start_offset = 0
    local _, left_spaces = text:find("^(%s*)")

    if left_spaces and left_spaces > 0 then
        -- Don't trim if first highlight starts before first non-space.
        if left_spaces <= highlights[1][1] then
            start_offset = left_spaces
            text = text:sub(start_offset + 1)
        end
    end

    -- Split the text to put the highlights.

    local chunks = {}
    for _, highlight in ipairs(highlights) do
        local start = highlight[1] - start_offset + 1
        local end_ = highlight[2] - start_offset

        if start > 1 then
            table.insert(chunks, {
                text:sub(1, start - 1),
                "AtlasResultsMatchText",
            })
        end

        table.insert(chunks, {
            text:sub(start, end_),
            "AtlasResultsMatchHighlight",
        })

        text = text:sub(end_ + 1)
        start_offset = start_offset + end_
    end

    if #text > 0 then
        table.insert(chunks, {
            text,
            "AtlasResultsMatchText",
        })
    end

    return chunks
end

--- Data to build the contents of the buffer for the view.
---
--- Each line contains a reference to the `items` index, the fold level,
--- and the label.
---
---@class atlas.view.bufdata.BufData
---@field items atlas.view.bufdata.ItemIndex
---@field lines string[]

---@param config atlas.Config
---@param tree atlas.view.Tree
---@param git_stats nil|atlas.impl.GitStats
---@param line_number_width integer
---@param items atlas.view.bufdata.ItemIndex
---@param lines string[]
---@param indent_prefix string
---@param fold_level integer
local function walk_tree(config, tree, git_stats, line_number_width, items, lines, indent_prefix, fold_level)
    local margin_by_depth = config.view.results.margin_by_depth

    -- Indent prefix for non-last children.
    local draw_tree = false
    local tree_hbar = " "
    local subtree_prefix_intermediate = ""
    local subtree_prefix_last = ""

    local previous_has_children = false

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
        local item_id = #items + 1

        ---@type table<string, atlas.view.bufdata.Column>
        local row_text = {}

        local has_children = not vim.tbl_isempty(item.children)

        -- The line in the buffer is just the identifier and the fold marker.
        do
            local buffer_line = tostring(item_id)

            if has_children or previous_has_children then
                buffer_line = string.format("%s{{{%d", buffer_line, fold_level)
            end

            table.insert(lines, buffer_line)
        end

        -- First column: filename.
        local filename_text = {} ---@type atlas.view.bufdata.Column
        row_text["000name"] = filename_text

        if type(margin_by_depth) == "function" then
            vim.list_extend(filename_text, margin_by_depth(fold_level, item))
        end

        -- Filename.
        if type(key) == "string" then
            if draw_tree and fold_level > 1 then
                table.insert(filename_text, {
                    string.format("%s%s%s", indent_prefix, is_last and "└" or "├", tree_hbar),
                    "AtlasResultsTreeMarker",
                })
            end

            -- Directories always has the trailing `/`.
            if item.kind == ItemKind.Directory then
                table.insert(filename_text, { key .. "/", "AtlasResultsItemDirectory" })
            else
                table.insert(filename_text, { key, "AtlasResultsItemFile" })
            end
        else
            if draw_tree then
                table.insert(filename_text, {
                    indent_prefix,
                    "AtlasResultsTreeMarker",
                })
            end
        end

        if item.line ~= nil then
            local line = tostring(item.line)
            local padding_width = line_number_width - #line
            local padding = padding_width > 0 and string.rep(" ", padding_width) or ""

            row_text["100line"] = {
                {
                    string.format(" %s%s", padding, line),
                    "AtlasResultsMatchLineNumber",
                },
            }
        end

        if item.text ~= nil then
            row_text["200text"] = render_text_column(item)
        end

        if git_stats and type(key) == "string" then
            local diff = git_stats.files[item.path]
            if diff then
                local added = string.format("+%d", diff.added)
                local removed = string.format("-%d", diff.removed)

                row_text["010diff"] = {
                    { string.rep(" ", git_stats.added_width - #added + 1), "None" },
                    { added, "AtlasResultsDiffAdd" },
                    { string.rep(" ", git_stats.removed_width - #removed + 2), "None" },
                    { removed, "AtlasResultsDiffDelete" },
                }
            end
        end

        -- Add the generated item to the list, and visit children nodes.

        ---@type atlas.view.bufdata.ItemData
        local item_data = {
            id = item_id,
            item = item,
            row_text = row_text,
        }

        table.insert(items, item_data)

        if has_children then
            previous_has_children = true

            walk_tree(
                config,
                item.children,
                git_stats,
                line_number_width,
                items,
                lines,
                is_last and subtree_prefix_last or subtree_prefix_intermediate,
                fold_level + 1
            )
        end
    end
end

---@param config atlas.Config
---@param tree atlas.view.Tree
---@param git_stats nil|atlas.impl.GitStats
---@param max_line_number integer
---@return atlas.view.bufdata.BufData
function M.render(config, tree, git_stats, max_line_number)
    local items = {}
    local lines = {}

    local line_number_width = #tostring(max_line_number)

    walk_tree(config, tree, git_stats, line_number_width, items, lines, "", 1)

    return {
        items = items,
        lines = lines,
    }
end

return M
