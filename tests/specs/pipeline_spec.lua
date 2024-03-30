local atlas = require("atlas")
local parser = require("atlas.filter_parser")
local pipeline = require("atlas.pipeline")

local testutils = require("tests.utils")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

describe("Pipeline Builder", function()
    it("simple filter", function()
        local specs = parser.parse("foo bar")
        local pl = pipeline.build(specs, atlas.defaults())

        assert_eq(pl.output, pipeline.PipeOutput.FileNames)

        testutils.assert_list_contains(pl.commands[1], { "rg", "--no-messages", "--files", "--null" })
        testutils.assert_list_contains(pl.commands[2], { "rg", "--null-data", "--regexp", "foo" })
        testutils.assert_list_contains(pl.commands[3], { "rg", "--null-data", "--regexp", "bar" })

        assert_eq(#pl.commands, 3)
    end)

    it("search file contents", function()
        local specs = parser.parse("foo -/first /second -bar")
        local pl = pipeline.build(specs, atlas.defaults())

        assert_eq(pl.output, pipeline.PipeOutput.JsonLines)

        testutils.assert_list_contains(pl.commands[1], { "rg", "--no-messages", "--files", "--null" })
        testutils.assert_list_contains(pl.commands[2], { "rg", "--null-data", "--regexp", "foo" })
        testutils.assert_list_contains(pl.commands[3], { "rg", "--null-data", "--invert-match", "--regexp", "bar" })
        testutils.assert_list_contains(
            pl.commands[4],
            { "xargs", "rg", "--null", "--files-without-match", "--regexp", "first" }
        )
        testutils.assert_list_contains(pl.commands[5], { "xargs", "rg", "--null", "--json", "--regexp", "second" })

        assert_eq(#pl.commands, 5)
    end)
end)
