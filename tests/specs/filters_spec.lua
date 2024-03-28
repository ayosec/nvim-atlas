local filters = require("atlas.filters")

local assert_eq = assert.are.same

describe("Filters", function()
    it("parse simple specifiers", function()
        local specs = filters.parse("foo bar")

        assert_eq(specs[1].kind, filters.FilterKind.Simple)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filters.FilterKind.Simple)
        assert_eq(specs[2].value, "bar")

        assert_eq(#specs, 2)
    end)

    it("ignore spaces", function()
        local specs = filters.parse("foo   bar  ")

        assert_eq(specs[1].value, "foo")
        assert_eq(specs[2].value, "bar")
        assert_eq(#specs, 2)
    end)
end)
