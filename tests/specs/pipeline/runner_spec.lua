require("plenary.async").tests.add_to_env()

local atlas = require("atlas")
local filter = require("atlas.filter")
local pipeline = require("atlas.pipeline")
local runner = require("atlas.pipeline.runner")

local testutils = require("tests.utils")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

local channel = a.control.channel

local config = atlas.default_config()
config.files.search_dir = function()
    return vim.env.LUAJIT_PATH
end

describe("Pipeline Runner", function()
    a.it("pipeline only with filenames", function()
        local tx, rx = channel.oneshot()

        local specs = filter.parse("ffi !a")
        local pl = pipeline.build(specs, config)

        runner.run(config, pl, function(result)
            local items = result.items
            assert_eq(#items, 2)

            local names = { items[1].file, items[2].file }
            testutils.assert_list_contains(names, { "doc/ext_ffi.html", "src/lib_ffi.c" })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    a.it("execute a complex pipeline", function()
        local tx, rx = channel.oneshot()

        local specs = filter.parse("asm.*6 !h !/xyz /req.*bit")
        local pl = pipeline.build(specs, config)

        runner.run(config, pl, function(result)
            local items = result.items
            assert_eq(#items, 1)

            assert_eq(items[1].file, "dynasm/dasm_x86.lua")
            assert_eq(items[1].line, 31)
            assert_eq(items[1].text, [[local bit = bit or require("bit")]])
            assert_eq(items[1].highlights, { { 19, 31 } })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    a.it("execute a single-filter pipeline", function()
        local tx, rx = channel.oneshot()

        local specs = filter.parse("/speed.*intern")
        local pl = pipeline.build(specs, config)

        runner.run(config, pl, function(result)
            local items = result.items
            assert_eq(#items, 1)

            assert_eq(items[1].file, "doc/changes.html")
            assert_eq(items[1].line, 493)
            assert_eq(items[1].text, "<li>Speed up string interning.</li>")
            assert_eq(items[1].highlights, { { 4, 26 } })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    a.it("can collect errors from the pipeline", function()
        local tx, rx = channel.oneshot()

        local specs = filter.parse("demo /[a-")
        local pl = pipeline.build(specs, config)

        runner.run(config, pl, function(result)
            tx("on_success invoked with " .. vim.inspect(result))
        end, function(stderr)
            assert(stderr:match("regex parse error"))
            assert(stderr:match("%[a-"))
            tx("")
        end)

        assert_eq(rx(), "")
    end)

    a.it("interrupt a pipeline", function()
        -- Use a "fake rg" to block the pipeline.
        local fakerg = vim.fn.tempname()
        vim.fn.writefile({ "#!/bin/sh", "exec sleep 10" }, fakerg)
        assert(vim.loop.fs_chmod(fakerg, 448)) -- 0o700

        local tmpconfig = atlas.default_config()
        tmpconfig.programs.ripgrep = fakerg

        -- Launch the pipeline.
        local tx, rx = channel.oneshot()

        local specs = filter.parse("/..")
        local pl = pipeline.build(specs, tmpconfig)

        local run = runner.run(tmpconfig, pl, function(result)
            tx("on_success invoked with " .. vim.inspect(result))
        end, function(stderr)
            tx("stderr=" .. stderr)
        end)

        -- Ripgrep should be blocked in the FIFO.
        local pids = vim.tbl_keys(run.process_handles)
        assert_eq(1, #pids)
        assert_eq("sleep", vim.api.nvim_get_proc(pids[1]).name)

        run:interrupt()

        assert_eq(rx(), "stderr=")
    end)
end)
