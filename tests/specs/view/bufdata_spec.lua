local BufData = require("atlas.view.bufdata")
local atlas = require("atlas")

local ItemKind = require("atlas.view").ItemKind

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

---@param bufdata atlas.view.bufdata.BufData
---@param row_text table<string, atlas.view.bufdata.Column>
---@param path string
---@param fold_level integer|nil
local function assert_buf_line(bufdata, row_text, path, fold_level)
    local line = table.remove(bufdata.lines, 1)

    if line == nil then
        error("No buffer line for " .. vim.inspect(path))
    end

    local _, _, item_id, level = line:find("(%d+)(.*)")
    item_id = tonumber(item_id)

    if #level > 0 then
        level = tonumber(level:gsub("{+", ""), 10)
    else
        level = nil
    end

    local item_data = bufdata.items[item_id]

    local row_text_values = {}
    for _, col in vim.spairs(item_data.row_text) do
        table.insert(row_text_values, col)
    end

    assert_eq(fold_level, level)
    assert_eq(path, item_data.item.path)
    assert_eq(row_text, row_text_values)
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

        local bufdata = BufData.render(atlas.default_config(), tree, nil, 300)

        local hlD = "AtlasResultsItemDirectory"
        local hlF = "AtlasResultsItemFile"
        local hlLN = "AtlasResultsMatchLineNumber"
        local hlMT = "AtlasResultsMatchText"
        local hlT = "AtlasResultsTreeMarker"

        local lines = {
            { { { "a/", hlD } } },
            { { { "├── ", hlT }, { "b/c/", hlD } } },
            { { { "│   ├── ", hlT }, { "1", hlF } } },
            { { { "│   └── ", hlT }, { "2", hlF } } },
            { { { "├── ", hlT }, { "x", hlF } } },
            { { { "│   ", hlT } }, { { "  10", hlLN } }, { { "first match", hlMT } } },
            { { { "│   ", hlT } }, { { " 200", hlLN } }, { { "second match", hlMT } } },
            { { { "└── ", hlT }, { "y", hlF } }, { { " 300", hlLN } }, { { "match in y", hlMT } } },
        }

        assert_buf_line(bufdata, lines[1], "a", 1)
        assert_buf_line(bufdata, lines[2], "a/b/c", 2)
        assert_buf_line(bufdata, lines[3], "a/b/c/1", nil)
        assert_buf_line(bufdata, lines[4], "a/b/c/2", nil)
        assert_buf_line(bufdata, lines[5], "a/x", 2)
        assert_buf_line(bufdata, lines[6], "a/x", nil)
        assert_buf_line(bufdata, lines[7], "a/x", nil)
        assert_buf_line(bufdata, lines[8], "a/y", 2)

        assert_eq(bufdata.lines, {})
    end)
end)
