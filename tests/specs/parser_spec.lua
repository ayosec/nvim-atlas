local parser = require("atlas.filter_parser")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

describe("Filter Parser", function()
    it("simple specifiers", function()
        local specs = parser.parse("foo bar")

        assert_eq(specs[1].kind, parser.FilterKind.Simple)
        assert_eq(specs[1].negated, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, parser.FilterKind.Simple)
        assert_eq(specs[2].negated, false)
        assert_eq(specs[2].value, "bar")

        assert_eq(#specs, 2)
    end)

    it("ignore spaces", function()
        local specs = parser.parse("foo   bar  ")

        assert_eq(specs[1].value, "foo")
        assert_eq(specs[2].value, "bar")
        assert_eq(#specs, 2)
    end)

    it("adjust regexs", function()
        local specs = parser.parse("foo bar*.lua")

        assert_eq(specs[1].kind, parser.FilterKind.Simple)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, parser.FilterKind.Simple)
        assert_eq(specs[2].value, "bar.*\\.lua")

        assert_eq(#specs, 2)
    end)

    it("find by file contents", function()
        local specs = parser.parse("foo /bar.*\\d")
        assert_eq(specs[1].kind, parser.FilterKind.Simple)
        assert_eq(specs[1].negated, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, parser.FilterKind.FileContents)
        assert_eq(specs[2].negated, false)
        assert_eq(specs[2].value, "bar.*\\d")

        assert_eq(#specs, 2)
    end)

    it("negate specifiers", function()
        local specs = parser.parse("-foo -/bar")
        assert_eq(specs[1].kind, parser.FilterKind.Simple)
        assert_eq(specs[1].negated, true)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, parser.FilterKind.FileContents)
        assert_eq(specs[2].negated, true)
        assert_eq(specs[2].value, "bar")

        assert_eq(#specs, 2)
    end)

    it("rest-of-the-line (//) specifier for file contents", function()
        local specs = parser.parse("foo //a bb ccc")
        assert_eq(specs[1].kind, parser.FilterKind.Simple)
        assert_eq(specs[1].negated, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, parser.FilterKind.FileContents)
        assert_eq(specs[2].negated, false)
        assert_eq(specs[2].value, "a bb ccc")

        assert_eq(#specs, 2)
    end)

    it("negated // filters", function()
        local specs = parser.parse("foo -//a bb ccc")
        assert_eq(specs[1].kind, parser.FilterKind.Simple)
        assert_eq(specs[1].negated, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, parser.FilterKind.FileContents)
        assert_eq(specs[2].negated, true)
        assert_eq(specs[2].value, "a bb ccc")

        assert_eq(#specs, 2)
    end)
end)
