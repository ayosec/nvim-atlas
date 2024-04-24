local History = require("atlas.history")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

---@diagnostic disable-next-line:undefined-field
local assert_is_nil = assert.is_nil

describe("History", function()
    it("add and get entries", function()
        local storage = {}
        local history = History.new(storage, 4)

        history:add("a1")
        history:add("a2")
        history:add("a3")
        history:add("a4")
        history:add("a5")
        history:add("a6")

        assert_eq(4, #storage)

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

    it("avoid duplicated entries", function()
        local storage = {}
        local history = History.new(storage, 10)

        history:add("b1")
        history:add("b2")
        history:add("b2")
        history:add("b1")

        assert_eq("b1", storage[1])
        assert_eq("b2", storage[2])
        assert_eq("b1", storage[3])
        assert_eq(3, #storage)
    end)
end)
