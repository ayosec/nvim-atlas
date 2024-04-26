local Text = require("atlas.text")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

describe("Text", function()
    it("toggle", function()
        assert_eq("abc def", Text.toggle("def", "abc"))
        assert_eq("def", Text.toggle("abc def", "abc"))
        assert_eq("ab ef hi", Text.toggle("ab cd ef cd hi", "cd"))
        assert_eq("ab ef ", Text.toggle("ab cd ef cd ", "cd"))
        assert_eq([[%x \a (x)]], Text.toggle([[%x \a %s\w( (x)]], [[%s\w(]]))
    end)
end)
