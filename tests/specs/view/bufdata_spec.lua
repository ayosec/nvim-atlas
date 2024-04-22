local BufData = require("atlas.view.bufdata")
local atlas = require("atlas")
local testutils = require("tests.utils")

local ItemKind = require("atlas.view").ItemKind

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

---@param bufdata atlas.view.bufdata.BufData
---@param label string
---@param path string
---@param fold_level integer|nil
local function assert_buf_line(bufdata, label, path, fold_level)
    local line = table.remove(bufdata.lines, 1)

    if line == nil then
        error("No buffer line for " .. vim.inspect(path))
    end

    local _, _, _, line_label = line:find("(%S+) (.+)")

    if #label == 0 then
        error("Unexpected format for path " .. vim.inspect(path) .. ": " .. vim.inspect(line))
    end

    local metadata = BufData.parse_metadata(line)
    assert(metadata ~= nil)

    local item = bufdata.items[metadata.item_id]

    assert_eq(item.path, path)
    assert_eq(item.kind, metadata.kind)
    assert_eq(fold_level, metadata.level)
    assert_eq(label, line_label)
end

describe("Buffer Data", function()
    it("build a tree only with filenames", function()
        ---@type atlas.view.Tree
        local tree = {
            ["a"] = {
                path = "a",
                kind = ItemKind.Directory,
                children = {
                    ["b/c"] = {
                        path = "a/b/c",
                        kind = ItemKind.Directory,
                        children = {
                            ["1"] = {
                                path = "a/b/c/1",
                                kind = ItemKind.File,
                                children = {},
                            },
                            ["2"] = {
                                path = "a/b/c/2",
                                kind = ItemKind.File,
                                children = {},
                            },
                        },
                    },
                    ["x"] = {
                        path = "a/x",
                        kind = ItemKind.File,
                        children = {
                            [1] = {
                                path = "a/x",
                                kind = ItemKind.ContentMatch,
                                line = 10,
                                text = "first match",
                                children = {},
                            },
                            [2] = {
                                path = "a/x",
                                kind = ItemKind.ContentMatch,
                                line = 200,
                                text = "second match",
                                children = {},
                            },
                        },
                    },
                    ["y"] = {
                        path = "a/y",
                        kind = ItemKind.ContentMatch,
                        line = 300,
                        text = "match in y",
                        children = {},
                    },
                },
            },
        }

        local bufdata = BufData.render(atlas.default_config(), tree, 300)

        local lines = testutils.lines([[
            a/
            ├── b/c/
            │   ├── 1
            │   └── 2
            ├── x
            │     @10:\tfirst match
            │    @200:\tsecond match
            └── y:\tmatch in y
        ]])

        assert_buf_line(bufdata, lines(), "a", 1)
        assert_buf_line(bufdata, lines(), "a/b/c", 2)
        assert_buf_line(bufdata, lines(), "a/b/c/1", nil)
        assert_buf_line(bufdata, lines(), "a/b/c/2", nil)
        assert_buf_line(bufdata, lines(), "a/x", 2)
        assert_buf_line(bufdata, lines(), "a/x", nil)
        assert_buf_line(bufdata, lines(), "a/x", nil)
        assert_buf_line(bufdata, lines(), "a/y", 2)

        assert_eq(bufdata.lines, {})
    end)
end)
