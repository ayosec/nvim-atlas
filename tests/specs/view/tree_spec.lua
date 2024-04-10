local Tree = require("atlas.view.tree")

local ResultsViewItemKind = require("atlas.view").ResultsViewItemKind

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

---@param tree ResultsViewTree
---@param parents string[]
---@param key string
---@param kind ResultsViewItemKind
---@return ResultsViewItem
local function assert_node(tree, parents, key, kind)
    local node = tree
    local full_paths = {}

    for _, p in ipairs(parents) do
        local next = node[p]
        if next == nil then
            error("Key " .. vim.inspect(p) .. " missing in " .. vim.inspect(node))
        end

        node = next.children
        table.insert(full_paths, p)
    end

    table.insert(full_paths, key)
    local full_path = table.concat(full_paths, "/")

    local target = node[key]
    if target == nil then
        error("Missing key " .. vim.inspect(key) .. " in " .. vim.inspect(node))
    end

    assert_eq(target.kind, kind)
    assert_eq(target.path, full_path)

    return target
end

describe("UI Tree", function()
    it("build a tree with a single result", function()
        ---@type PipelineResult[]
        local results = {
            { file = "a/b/c/d/1" },
        }

        local tree = Tree.build(results)

        assert_node(tree, {}, "a/b/c/d", ResultsViewItemKind.Directory)
        assert_node(tree, { "a/b/c/d" }, "1", ResultsViewItemKind.File)
    end)

    it("build a tree only with filenames", function()
        ---@type PipelineResult[]
        local results = {
            { file = "a/b/c/d/1" },
            { file = "a/b/c/d/2" },
            { file = "a/b/d/3" },
            { file = "a/b/d/e/e/4" },
            { file = "a/b/d/e/e/5" },
            { file = "a/6" },
            { file = "7" },
            { file = "f/8" },
            { file = "f/9" },
            { file = "g/h/i/10" },
            { file = "gg/h/11" },
            { file = "j/k/x/m/12" },
            { file = "j/k/y/m/13" },
            { file = "j/k/y/m/14" },
            { file = "n/n/n/n/n/n/15" },
            { file = "n/n/n/n/n/n/16" },
            { file = "n/n/n/n/n/17" },
            { file = "n/n/n/18" },
        }

        local tree = Tree.build(results)

        local F = ResultsViewItemKind.File
        local D = ResultsViewItemKind.Directory

        assert_node(tree, { "a" }, "b", D)
        assert_node(tree, { "a", "b" }, "c/d", D)
        assert_node(tree, { "a", "b" }, "d", D)
        assert_node(tree, { "a", "b", "d" }, "e/e", D)
        assert_node(tree, { "j/k" }, "x/m", D)
        assert_node(tree, { "j/k" }, "y/m", D)
        assert_node(tree, { "n/n/n" }, "n/n", D)
        assert_node(tree, { "n/n/n", "n/n" }, "n", D)

        assert_node(tree, { "a", "b", "c/d" }, "1", F)
        assert_node(tree, { "a", "b", "c/d" }, "2", F)
        assert_node(tree, { "a", "b", "d" }, "3", F)
        assert_node(tree, { "a", "b", "d", "e/e" }, "4", F)
        assert_node(tree, { "a", "b", "d", "e/e" }, "5", F)
        assert_node(tree, { "a" }, "6", F)
        assert_node(tree, {}, "7", F)
        assert_node(tree, { "f" }, "8", F)
        assert_node(tree, { "f" }, "9", F)
        assert_node(tree, { "g/h/i" }, "10", F)
        assert_node(tree, { "gg/h" }, "11", F)
        assert_node(tree, { "j/k", "x/m" }, "12", F)
        assert_node(tree, { "j/k", "y/m" }, "13", F)
        assert_node(tree, { "j/k", "y/m" }, "14", F)
        assert_node(tree, { "n/n/n", "n/n", "n" }, "15", F)
        assert_node(tree, { "n/n/n", "n/n", "n" }, "16", F)
        assert_node(tree, { "n/n/n", "n/n" }, "17", F)
        assert_node(tree, { "n/n/n" }, "18", F)
    end)

    it("build a tree with file matches", function()
        ---@type PipelineResult[]
        local results = {
            { file = "a/b/1", line = 10, text = "x0" },
            { file = "a/b/2", line = 15, text = "x1" },
            { file = "a/b/c/3", line = 20, text = "x2" },
            { file = "a/b/c/3", line = 20, text = "[IGNORED]" },
            { file = "a/b/c/3", line = 25, text = "x3" },
            { file = "a/b/c/3", line = 30, text = "x4" },
            { file = "a/b/c/4", line = 35, text = "x5" },
        }

        local tree = Tree.build(results)

        local F = ResultsViewItemKind.File
        local D = ResultsViewItemKind.Directory
        local C = ResultsViewItemKind.ContentMatch

        assert_node(tree, {}, "a/b", D)
        assert_node(tree, { "a/b" }, "c", D)

        local f

        f = assert_node(tree, { "a/b" }, "1", C)
        assert_eq(f.line, 10)
        assert_eq(f.text, "x0")

        f = assert_node(tree, { "a/b" }, "2", C)
        assert_eq(f.line, 15)
        assert_eq(f.text, "x1")

        f = assert_node(tree, { "a/b", "c" }, "3", F)

        assert_eq(f.children[20].path, "a/b/c/3")
        assert_eq(f.children[20].kind, C)
        assert_eq(f.children[20].line, 20)
        assert_eq(f.children[20].text, "x2")

        assert_eq(f.children[25].path, "a/b/c/3")
        assert_eq(f.children[25].kind, C)
        assert_eq(f.children[25].line, 25)
        assert_eq(f.children[25].text, "x3")

        assert_eq(f.children[30].path, "a/b/c/3")
        assert_eq(f.children[30].kind, C)
        assert_eq(f.children[30].line, 30)
        assert_eq(f.children[30].text, "x4")

        assert_eq(vim.tbl_count(f.children), 3)

        f = assert_node(tree, { "a/b", "c" }, "4", C)
        assert_eq(f.line, 35)
        assert_eq(f.text, "x5")
    end)
end)
