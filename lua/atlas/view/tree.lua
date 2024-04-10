local M = {}

local ResultsViewItemKind = require("atlas.view").ResultsViewItemKind

--- Find the node for the `path`. It may split an existing node if it shares
--- a prefix with the `path`.
---
---@param tree ResultsViewTree
---@param path string
---@param parent_node ResultsViewItem?
---@param parent_shared_prefix string
---@return ResultsViewItem?
local function find_parent_node(tree, path, parent_node, parent_shared_prefix)
    -- If `path` is already a node of the tree, we don't need to find
    -- the shared prefix.
    if tree[path] ~= nil then
        return parent_node
    end

    -- Find a key with a shared prefix.

    local longest_shared_prefix = ""
    local longest_shared_prefix_node = nil
    local longest_shared_prefix_key = ""

    for key, node in pairs(tree) do
        if type(key) == "string" then
            local shared_prefix = ""
            local path_iter = vim.gsplit(path, "/")

            for n in vim.gsplit(node.path, "/") do
                local p = path_iter()

                if n ~= p or p == nil then
                    break
                end

                local sep = shared_prefix == "" and "" or "/"
                shared_prefix = shared_prefix .. sep .. n
            end

            if #shared_prefix > #longest_shared_prefix then
                longest_shared_prefix = shared_prefix
                longest_shared_prefix_key = key
                longest_shared_prefix_node = node
            end
        end
    end

    if longest_shared_prefix_node ~= nil then
        local shared_prefix = longest_shared_prefix
        local sp_node = longest_shared_prefix_node

        -- Compute the key for the new node, discarding the previous shared prefix.
        local new_node_key
        if parent_shared_prefix == "" then
            new_node_key = shared_prefix
        else
            new_node_key = shared_prefix:sub(#parent_shared_prefix + 2)
        end

        if new_node_key == "" then
            -- If no children shares a prefix with the target path, the new
            -- node is added to the parent.
            return parent_node
        end

        -- If the key for the new node is already present, repeat this process
        -- in its subtree.
        local existing_node = tree[new_node_key]
        if existing_node ~= nil then
            local node = find_parent_node(existing_node.children, path, existing_node, shared_prefix)
            assert(node)
            return node
        end

        -- Split the node with the shared prefix. The new node contains the
        -- new node and the node with the matched prefix.
        local split_node = {
            kind = ResultsViewItemKind.Directory,
            path = shared_prefix,
            children = {
                [sp_node.path:sub(#shared_prefix + 2)] = sp_node,
            },
        }

        tree[longest_shared_prefix_key] = nil
        tree[new_node_key] = split_node
        return split_node
    end

    return parent_node
end

---@param parent ResultsViewTree
---@param parent_path string
---@param result PipelineResult
local function append_node(parent, parent_path, result)
    local relative_path = result.file

    if parent_path ~= "" then
        local prefix = parent_path .. "/"
        assert(vim.startswith(relative_path, prefix))

        relative_path = relative_path:sub(#prefix + 1)
    end

    local target
    local dirname = vim.fs.dirname(relative_path)

    if dirname ~= "." then
        if parent[dirname] == nil then
            parent[dirname] = {
                kind = ResultsViewItemKind.Directory,
                path = vim.fs.dirname(result.file),
                children = {},
            }
        end

        target = parent[dirname].children
    else
        target = parent
    end

    -- Add the node the tree.
    --
    -- If the `PipelineResult` has a line number, the node for the file
    -- is either a kind=ContentMatch (for a single line), or a kind=File
    -- (for multiple lines, in the `children` field).

    local file_node_key = vim.fs.basename(relative_path)

    ---@type ResultsViewItem
    local file_node = target[file_node_key]

    if file_node == nil then
        file_node = {
            kind = ResultsViewItemKind.File,
            path = result.file,
            children = {},
        }

        target[file_node_key] = file_node
    end

    local line_key = result.line

    if line_key ~= nil then
        local ContentMatch = ResultsViewItemKind.ContentMatch

        if file_node.kind == ContentMatch then
            -- Replacing a node with a single result.
            --
            -- A kind=File node is created, and the previous node is
            -- moved into it.

            target[file_node_key] = {
                kind = ResultsViewItemKind.File,
                path = result.file,
                children = {
                    [result.line] = file_node,
                },
            }
        elseif vim.tbl_isempty(file_node.children) then
            -- Just-created node.
            --
            -- Change its kind and add line/text fields.

            file_node.kind = ContentMatch
            file_node.line = result.line
            file_node.text = result.text
        else
            -- Node with other matches.
            --
            -- Add the result only if the line is not occupied.

            if file_node.children[line_key] == nil then
                file_node.children[line_key] = {
                    kind = ContentMatch,
                    path = result.file,
                    line = result.line,
                    text = result.text,
                    children = {},
                }
            end
        end
    end
end

--- Build a tree from the results of a search pipeline.
---
---@param results PipelineResult[]
---@return ResultsViewTree
function M.build(results)
    ---@type ResultsViewTree
    local tree = {}

    for _, result in ipairs(results) do
        local dirname = vim.fs.dirname(result.file)

        local parent_tree, parent_path

        if dirname ~= "." then
            local parent = find_parent_node(tree, dirname, nil, "")
            if parent ~= nil then
                parent_tree = parent.children
                parent_path = parent.path
            end
        end

        if parent_tree ~= nil then
            append_node(parent_tree, parent_path, result)
        else
            append_node(tree, "", result)
        end
    end

    return tree
end

return M
