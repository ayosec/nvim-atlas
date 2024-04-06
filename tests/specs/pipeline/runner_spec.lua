require("plenary.async").tests.add_to_env()

local atlas = require("atlas")
local parser = require("atlas.filter_parser")
local pipeline = require("atlas.pipeline")
local runner = require("atlas.pipeline.runner")

local testutils = require("tests.utils")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

local channel = a.control.channel

local config = atlas.defaults()
config.files.search_dir = function()
    return "tests/fixtures/demoproject"
end

describe("Pipeline Runner", function()
    a.it("pipeline only with filenames", function()
        local tx, rx = channel.oneshot()

        local specs = parser.parse("b e")
        local pl = pipeline.build(specs, config)

        runner.run(config, pl, function(results)
            assert_eq(#results, 2)

            local names = { results[1].file, results[2].file }
            testutils.assert_list_contains(names, { "b/blue", "b/yellow" })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    a.it("execute a complex pipeline", function()
        local tx, rx = channel.oneshot()

        local specs = parser.parse("a*r -d -/nothing /c.*a.*t")
        local pl = pipeline.build(specs, config)

        runner.run(config, pl, function(results)
            assert_eq(#results, 1)

            assert_eq(results[1].file, "a/green")
            assert_eq(results[1].line, 3)
            assert_eq(results[1].text, "angoribus. Quocirca eodem modo sapiens erit")

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    a.it("execute a single-filter pipeline", function()
        local tx, rx = channel.oneshot()

        local specs = parser.parse("/stoi.*irr")
        local pl = pipeline.build(specs, config)

        runner.run(config, pl, function(results)
            assert_eq(#results, 1)

            assert_eq(results[1].file, "b/blue")
            assert_eq(results[1].line, 2)
            assert_eq(results[1].text, "Stoicos irridente, statua est in eo, quod sit a")

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    a.it("can collect errors from the pipeline", function()
        local tx, rx = channel.oneshot()

        local specs = parser.parse("demo /[a-")
        local pl = pipeline.build(specs, config)

        runner.run(config, pl, function(results)
            tx("on_success invoked with " .. vim.inspect(results))
        end, function(stderr)
            assert(stderr:match("regex parse error"))
            assert(stderr:match("%[a-"))
            tx("")
        end)

        assert_eq(rx(), "")
    end)
end)
