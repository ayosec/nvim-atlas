local atlas = require("atlas")
local filter = require("atlas.filter")
local pipeline = require("atlas.pipeline")

local testutils = require("tests.utils")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

local RG = vim.fn.exepath("rg")
local XARGS = vim.fn.exepath("xargs")

describe("Pipeline Builder", function()
    it("simple filter", function()
        local specs = filter.parse("foo bar")
        local pl = pipeline.build(specs, atlas.default_config())

        assert_eq(pl.output_kind, pipeline.PipeOutput.FileNames)

        testutils.assert_list_contains(pl.commands[1], { RG, "--no-messages", "--files", "--null" })
        testutils.assert_list_contains(pl.commands[2], { RG, "--null-data", "--regexp", "foo" })
        testutils.assert_list_contains(pl.commands[3], { RG, "--null-data", "--regexp", "bar" })

        assert_eq(#pl.commands, 3)
    end)

    it("search file contents", function()
        local specs = filter.parse("foo -/first /second /third -bar =fix1 -=/fix2")
        local pl = pipeline.build(specs, atlas.default_config())

        assert_eq(pl.output_kind, pipeline.PipeOutput.JsonLines)

        testutils.assert_list_contains(pl.commands[1], { RG, "--no-messages", "--files", "--null" })
        testutils.assert_list_contains(pl.commands[2], { RG, "--null-data", "--regexp", "foo" })
        testutils.assert_list_contains(pl.commands[3], { RG, "--null-data", "--invert-match", "--regexp", "bar" })
        testutils.assert_list_contains(pl.commands[4], { RG, "--null-data", "--fixed-strings", "--regexp", "fix1" })
        testutils.assert_list_contains(
            pl.commands[5],
            { XARGS, RG, "--null", "--files-without-match", "--regexp", "first" }
        )
        testutils.assert_list_contains(
            pl.commands[6],
            { XARGS, RG, "--null", "--files-with-matches", "--regexp", "third" }
        )
        testutils.assert_list_contains(
            pl.commands[7],
            { XARGS, RG, "--null", "--files-without-match", "--fixed-strings", "--regexp", "fix2" }
        )
        testutils.assert_list_contains(pl.commands[8], { XARGS, RG, "--null", "--json", "--regexp", "second" })

        assert_eq(#pl.commands, 8)
    end)

    it("specialize single filter for file contents", function()
        local specs = filter.parse("/abc")
        local pl = pipeline.build(specs, atlas.default_config())

        assert_eq(pl.output_kind, pipeline.PipeOutput.JsonLines)

        testutils.assert_list_contains(pl.commands[1], { RG, "--no-messages", "--json", "--regexp", "abc" })

        assert_eq(#pl.commands, 1)
    end)
end)
