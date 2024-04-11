local BufData = require("atlas.view.bufdata")
local atlas = require("atlas")

local ItemKind = require("atlas.view").ItemKind

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

---@param bufdata atlas.view.bufdata.BufData
---@param path string
---@param fold_level integer|nil
---@param label string
local function assert_buf_line(bufdata, path, fold_level, label)
    local line = table.remove(bufdata.lines, 1)

    if line == nil then
        error("No buffer line for " .. vim.inspect(path))
    end

    local _, _, metadata_text, line_label = line:find("(%S+) (.+)")

    if #metadata_text == 0 or #label == 0 then
        error("Unexpected format for path " .. vim.inspect(path) .. ": " .. vim.inspect(line))
    end

    local metadata = BufData.parse_metadata(metadata_text)
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
                                line = 100,
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
                },
            },
        }

        local bufdata = BufData.render(atlas.defaults(), tree)

        assert_buf_line(bufdata, "a", 1, "a/")
        assert_buf_line(bufdata, "a/b/c", 2, "   b/c/")
        assert_buf_line(bufdata, "a/b/c/1", nil, "      1")
        assert_buf_line(bufdata, "a/b/c/2", nil, "      2")
        assert_buf_line(bufdata, "a/x", 2, "   x")
        assert_buf_line(bufdata, "a/x", nil, "      @100: first match")
        assert_buf_line(bufdata, "a/x", nil, "      @200: second match")

        assert_eq(bufdata.lines, {})
    end)
end)
