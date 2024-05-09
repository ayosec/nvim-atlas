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
    it("basic filter", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("luajit.[ch]$").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
            local items = result.items
            assert_eq(#items, 2)

            local names = { items[1].file, items[2].file }
            testutils.assert_list_contains(names, { "src/luajit.c", "src/luajit.h" })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    it("exclude filenames", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("ffi !a").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
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

    it("filenames with content filter", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("_vm !event /LOG /target").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
            local items = result.items
            assert_eq(#items, 1)

            assert_eq(items[1].file, "src/lj_vm.h")
            assert_eq(items[1].line, 63)
            assert_eq(items[1].text, [[#if defined(LUAJIT_NO_LOG2) || LJ_TARGET_X86ORX64]])
            assert_eq(items[1].highlights, { { 22, 25 }, { 34, 40 } })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    it("execute a complex pipeline", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("asm.*6 !h !/xyz /req.*bit").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
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

    it("multiple content filters", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("=.h /memcpy /sizeof").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
            local items = result.items
            assert_eq(#items, 1)

            assert_eq(items[1].file, "src/lj_ctype.h")
            assert_eq(items[1].line, 390)
            assert_eq(items[1].text, [[   memcpy((cts)->hash, savects_.hash, sizeof(savects_.hash)))]])
            assert_eq(items[1].highlights, { { 3, 9 }, { 38, 44 } })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    it("combine content and exclude filters", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("=.h /#define /HOOK_EVENT !/hook_save").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
            local items = result.items
            assert_eq(#items, 1)

            assert_eq(items[1].file, "src/lj_obj.h")
            assert_eq(items[1].line, 551)
            assert_eq(items[1].text, "#define HOOK_EVENTMASK\t\t0x0f")
            assert_eq(items[1].highlights, { { 0, 7 }, { 8, 18 } })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    it("overlapped highlights", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("cparse /<4 /<< =/c&15) /15.* =/(cp->c").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
            local items = result.items
            assert_eq(#items, 1)

            assert_eq(items[1].file, "src/lj_cparse.c")
            assert_eq(items[1].line, 242)
            assert_eq(items[1].text, "\t  c = (c<<4) + (lj_char_isdigit(cp->c) ? cp->c-'0' : (cp->c&15)+9);")
            assert_eq(items[1].highlights, { { 9, 12 }, { 32, 38 }, { 54, 68 } })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    it("execute a single-filter pipeline", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("/speed.*intern").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
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

    it("fixed-strings for content filters", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("=!/*J =c. =//GCtrace *T)").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
            local items = result.items
            assert_eq(#items, 1)

            assert_eq(items[1].file, "src/lj_gc.c")
            assert_eq(items[1].line, 232)
            assert_eq(items[1].text, "static void gc_traverse_trace(global_State *g, GCtrace *T)")
            assert_eq(items[1].highlights, { { 47, 58 } })

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    it("filenames with content", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("opt !?IR_ADD ?REF_FIRST =?ins++)").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
            local items = result.items

            assert_eq(#items, 1)
            assert_eq(items[1].file, "src/lj_opt_loop.c")

            tx("")
        end, function(stderr)
            tx("on_error invoked with " .. vim.inspect(stderr))
        end)

        assert_eq(rx(), "")
    end)

    it("can collect errors from the pipeline", function()
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("demo /[a-").specs
        local program = SearchProgram.build(specs, config)

        Runner.run(config, program, function(result)
            tx("on_success invoked with " .. vim.inspect(result))
        end, function(stderr)
            assert(stderr:match("regex parse error"))
            assert(stderr:match("%[a-"))
            tx("")
        end)

        assert_eq(rx(), "")
    end)

    it("interrupt a pipeline", function()
        -- Use a "fake rg" to block the pipeline.
        local fakerg = vim.fn.tempname()
        vim.fn.writefile({ "#!/bin/sh", "exec sleep 10" }, fakerg)
        assert(vim.loop.fs_chmod(fakerg, 448)) -- 0o700

        local tmpconfig = Atlas.default_config()
        tmpconfig.programs.ripgrep = fakerg

        -- Launch the pipeline.
        local tx, rx = testutils.oneshot()

        local specs = Filter.parse("/..").specs
        local program = SearchProgram.build(specs, tmpconfig)

        local run = Runner.run(tmpconfig, program, function(result)
            tx("on_success invoked with " .. vim.inspect(result))
        end, function(stderr)
            tx("stderr=" .. stderr)
        end)

        -- Ripgrep should be blocked in the FIFO.
        local pids = vim.tbl_keys(run.command_pipelines[1].process_handles)
        assert_eq(1, #pids)
        assert_eq("sleep", vim.api.nvim_get_proc(pids[1]).name)

        run:interrupt()

        assert_eq(rx(), "stderr=")
    end)
end)
