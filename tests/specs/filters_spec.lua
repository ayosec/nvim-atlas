local filters = require("atlas.filters")

local assert_eq = assert.are.same

describe("Filters", function()
    it("parse simple specifiers", function()
        local specs = filters.parse("foo bar")

        assert_eq(specs[1].kind, filters.FilterKind.Simple)
        assert_eq(specs[1].negated, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filters.FilterKind.Simple)
        assert_eq(specs[2].negated, false)
        assert_eq(specs[2].value, "bar")

        assert_eq(#specs, 2)
    end)

    it("ignore spaces", function()
        local specs = filters.parse("foo   bar  ")

        assert_eq(specs[1].value, "foo")
        assert_eq(specs[2].value, "bar")
        assert_eq(#specs, 2)
    end)

    it("adjust regexs", function()
        local specs = filters.parse("foo bar*.lua")

        assert_eq(specs[1].kind, filters.FilterKind.Simple)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filters.FilterKind.Simple)
        assert_eq(specs[2].value, "bar.*\\.lua")

        assert_eq(#specs, 2)
    end)

    it("find by file contents", function()
        local specs = filters.parse("foo /bar.*\\d")
        assert_eq(specs[1].kind, filters.FilterKind.Simple)
        assert_eq(specs[1].negated, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filters.FilterKind.FileContents)
        assert_eq(specs[2].negated, false)
        assert_eq(specs[2].value, "bar.*\\d")

        assert_eq(#specs, 2)
    end)

    it("negate specifiers", function()
        local specs = filters.parse("-foo -/bar")
        assert_eq(specs[1].kind, filters.FilterKind.Simple)
        assert_eq(specs[1].negated, true)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filters.FilterKind.FileContents)
        assert_eq(specs[2].negated, true)
        assert_eq(specs[2].value, "bar")

        assert_eq(#specs, 2)
    end)
end)
