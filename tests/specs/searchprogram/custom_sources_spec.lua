local Atlas = require("atlas")
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
end)
