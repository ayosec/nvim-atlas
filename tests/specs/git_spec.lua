local Git = require("atlas.git")

local testutils = require("tests.utils")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

describe("Filter Parser", function()
    it("simple specifiers", function()
        -- Initialize a dummy repository with some changes.

        local workdir = vim.fn.tempname()
        vim.fn.mkdir(workdir)

        vim.fn.writefile({ "1", "2" }, workdir .. "/one")
        vim.fn.writefile({ "3", "4" }, workdir .. "/two")
        vim.fn.writefile({ "5" }, workdir .. "/three")

        local initcmds = {
            { "init" },
            { "add", "one", "two", "three" },
            { "commit", "--message", "nothing" },
        }

        for _, args in ipairs(initcmds) do
            local cmd = { "git", "-c", "user.email=atlas", "-c", "user.name=atlas" }
            vim.list_extend(cmd, args)
            testutils.run_command(cmd, workdir)
        end

        vim.fn.writefile({ "1", "x" }, workdir .. "/one")
        vim.fn.writefile({ "3", "4" }, workdir .. "/two")
        vim.fn.writefile({ "5", "6", "7", "8" }, workdir .. "/three")

        -- Get the diff stats.
        local stats = nil

        Git.stats(workdir, "git", { "HEAD" }, function(code, s)
            assert_eq(0, code)
            stats = s
        end)

        vim.wait(1000, function()
            return stats ~= nil
        end)

        assert(stats)

        assert_eq(1, stats.files["one"].added)
        assert_eq(1, stats.files["one"].removed)

        assert_eq(nil, stats.files["two"])

        assert_eq(3, stats.files["three"].added)
        assert_eq(0, stats.files["three"].removed)
    end)
end)
