local Filter = require("atlas.filter")
local Pipeline = require("atlas.pipeline")
local atlas = require("atlas")

local testutils = require("tests.utils")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

local RG = vim.fn.exepath("rg")
local XARGS = vim.fn.exepath("xargs")

describe("Pipeline Builder", function()
    it("simple filter", function()
        local specs = Filter.parse("foo bar")
        local pl = Pipeline.build(specs, atlas.default_config())

        assert_eq(pl.output_kind, Pipeline.PipeOutput.FileNames)

        testutils.assert_list_contains(pl.commands[1], { RG, "--no-messages", "--files", "--null" })
        testutils.assert_list_contains(pl.commands[2], { RG, "--null-data", "--regexp", "foo" })
        testutils.assert_list_contains(pl.commands[3], { RG, "--null-data", "--regexp", "bar" })

        assert_eq(#pl.commands, 3)
    end)

    it("search file contents", function()
        local specs = Filter.parse("foo -/first /second /third -bar =fix1 -=/fix2")
        local pl = Pipeline.build(specs, atlas.default_config())

        assert_eq(pl.output_kind, Pipeline.PipeOutput.JsonLines)

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
        local specs = Filter.parse("/abc")
        local pl = Pipeline.build(specs, atlas.default_config())

        assert_eq(pl.output_kind, Pipeline.PipeOutput.JsonLines)

        testutils.assert_list_contains(pl.commands[1], { RG, "--no-messages", "--json", "--regexp", "abc" })

        assert_eq(#pl.commands, 1)
    end)

    it("ignore-case argument", function()
        local tests = {
            { false, "--ignore-case" },
            { true, "--case-sensitive" },
            { "smart", "--smart-case" },
        }

        local filters = { "foo", "/foo", "foo /bar", "foo1 /bar foo2 /bar2" }

        for _, test in ipairs(tests) do
            for _, filter in ipairs(filters) do
                local cfg = atlas.default_config()
                cfg.search.case_sensitivity = test[1]

                local specs = Filter.parse(filter)
                local pl = Pipeline.build(specs, cfg)

                for _, cmd in ipairs(pl.commands) do
                    testutils.assert_list_contains(cmd, { test[2] })
                end
            end
        end
    end)
end)
