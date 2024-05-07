local Pipeline = require("atlas.searchprogram.pipeline")
local Stderr = require("atlas.searchprogram.stderr")

local testutils = require("tests.utils")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

describe("Pipeline Commands", function()
    it("execute a single command", function()
        local tx, rx = testutils.oneshot()
        local output = ""

        local run = Pipeline.run {
            commands = { { "sh", "-c", "echo A\necho B" } },

            on_data = function(_, data)
                output = output .. data
            end,

            on_exit = function(_, _, success)
                tx(success)
            end,
        }

        assert_eq(1, run.active)
        assert_eq(true, rx())
        assert_eq(0, run.active)

        assert_eq("A\nB\n", output)
    end)

    it("collect stderr", function()
        local tx, rx = testutils.oneshot()

        local stderr = Stderr.collector()
        local echo = { "sh", "-c", "printf AB 1>&2" }

        local run = Pipeline.run {
            commands = { echo, echo },
            stderr = stderr,

            on_data = function() end,

            on_exit = function(r, _, success)
                if r.active == 0 then
                    tx(success)
                end
            end,
        }

        stderr:close_write()

        assert_eq(2, run.active)
        assert_eq(true, rx())

        assert_eq("ABAB", stderr:get())
    end)

    it("send data to the pipeline", function()
        local output = ""
        local tx, rx = testutils.oneshot()

        local run = Pipeline.run {
            open_stdin = true,
            commands = {
                { "tr", "a-z", "A-Z" },
                { "tail", "-c", "4" },
                { "head", "-c", "3" },
            },

            on_data = function(_, data)
                output = output .. data
            end,

            on_exit = function(r, _, success)
                if r.active == 0 then
                    tx(success)
                end
            end,
        }

        assert_eq(3, run.active)

        assert(run.stdin)
        run.stdin:write("abcdef")
        run.stdin:write("ghijkl")
        run.stdin:close()

        assert_eq(true, rx())
        assert_eq("IJK", output)
    end)

    it("interrupt a pipeline", function()
        local tx, rx = testutils.oneshot()

        local run = Pipeline.run {
            commands = {
                { "sleep", "100" },
                { "cat" },
                { "cat" },
            },

            on_data = function() end,

            on_exit = function(r, _, success)
                if r.active == 0 then
                    tx(success)
                end
            end,
        }

        assert_eq(3, run.active)

        local pids = vim.tbl_keys(run.process_handles)
        table.sort(pids)

        assert_eq(3, #pids)
        assert_eq("sleep", vim.api.nvim_get_proc(pids[1]).name)
        assert_eq("cat", vim.api.nvim_get_proc(pids[2]).name)
        assert_eq("cat", vim.api.nvim_get_proc(pids[3]).name)

        run:interrupt()

        assert_eq(false, rx())

        assert_eq(nil, vim.api.nvim_get_proc(pids[1]))
        assert_eq(nil, vim.api.nvim_get_proc(pids[2]))
        assert_eq(nil, vim.api.nvim_get_proc(pids[3]))
    end)
end)
