local History = require("atlas.history")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

---@diagnostic disable-next-line:undefined-field
local assert_is_nil = assert.is_nil

local viml = vim.api.nvim_eval

describe("History", function()
    it("add and get entries", function()
        local history = History.new("hist_test_1", 4)
        history:add("a1")
        history:add("a2")
        history:add("a3")
        history:add("a4")
        history:add("a5")
        history:add("a6")

        assert_eq(1, viml("type(g:hist_test_1) == type([])"))
        assert_eq(4, viml("len(g:hist_test_1)"))

        assert_eq("a6", history:go(1))
        assert_eq("a5", history:go(1))
        assert_eq("a4", history:go(1))
        assert_eq("a3", history:go(1))
        assert_is_nil(history:go(1))
        assert_is_nil(history:go(1))

        assert_eq("a4", history:go(-1))
        assert_eq("a5", history:go(-1))
        assert_eq("a6", history:go(-1))
        assert_is_nil(history:go(-1))
        assert_is_nil(history:go(-1))

        assert_eq("a5", history:go(1))
    end)

    it("replace invalid variables", function()
        vim.g.hist_test_2 = "broken"
        local history = History.new("hist_test_2", 4)

        history:add("aX")
        assert_eq("aX", viml("get(g:hist_test_2, 0)"))
    end)

    it("avoid duplicated entries", function()
        local history = History.new("hist_test_3", 10)

        history:add("b1")
        history:add("b2")
        history:add("b2")
        history:add("b1")

        assert_eq("b1", viml("get(g:hist_test_3, 0)"))
        assert_eq("b2", viml("get(g:hist_test_3, 1)"))
        assert_eq("b1", viml("get(g:hist_test_3, 2)"))
        assert_eq(3, viml("len(g:hist_test_3)"))
    end)
end)
