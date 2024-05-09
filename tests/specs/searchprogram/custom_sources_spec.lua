local Atlas = require("atlas")
local DirectSearch = require("atlas.directsearch")
local Filter = require("atlas.filter")
local Runner = require("atlas.searchprogram.runner")
local SearchProgram = require("atlas.searchprogram")

local testutils = require("tests.utils")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

local config = Atlas.default_config()
config.files.search_dir = function()
    return vim.env.LUAJIT_PATH
end

describe("Pipeline Runner", function()
    it("files with a filter", function()
        local tx, rx = testutils.oneshot()

        ---@type atlas.sources.Response
        local source = {
            files = { "src/lib_ffi.c", "doc/ext_ffi.html" },
        }

        local specs = Filter.parse("=.c").specs
        local program = SearchProgram.build(specs, config, source)

        Runner.run(config, program, function(result)
            local items = result.items
            assert_eq(#items, 1)
            assert_eq(items[1].file, "src/lib_ffi.c")

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    it("filter on custom items", function()
        ---@type atlas.sources.Response
        local source = {
            items = {
                { file = "red", line = 123, text = "a bb cc.c ddd" },
                { file = "red", line = 124, text = "12 3456 789" },
                { file = "red", line = 125, text = "aabcd" },
                { file = "green", line = 987, text = "abcd eee ff g" },
                { file = "blue", line = 5 },
                { file = "blue", line = 6, text = "aaa" },
            },
        }

        local filter = Filter.parse("/a+ re !g =!/c.")
        local results = DirectSearch.try_search(filter, source)
        assert(results)

        local items = results.items
        assert_eq(items[1].file, "red")
        assert_eq(items[1].line, 125)
        assert_eq(items[1].text, "aabcd")

        assert_eq(#items, 1)
    end)
end)
