local filter = require("atlas.filter")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

describe("Filter Parser", function()
    it("simple specifiers", function()
        local specs = filter.parse("foo bar").specs

        assert_eq(specs[1].kind, filter.FilterKind.Simple)
        assert_eq(specs[1].exclude, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filter.FilterKind.Simple)
        assert_eq(specs[2].exclude, false)
        assert_eq(specs[2].value, "bar")

        assert_eq(#specs, 2)
    end)

    it("ignore spaces", function()
        local specs = filter.parse("foo   bar  ").specs

        assert_eq(specs[1].value, "foo")
        assert_eq(specs[2].value, "bar")
        assert_eq(#specs, 2)
    end)

    it("find by file contents", function()
        local specs = filter.parse("foo /bar.*\\d").specs
        assert_eq(specs[1].kind, filter.FilterKind.Simple)
        assert_eq(specs[1].exclude, false)
        assert_eq(specs[1].fixed_string, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filter.FilterKind.FileContents)
        assert_eq(specs[2].exclude, false)
        assert_eq(specs[2].fixed_string, false)
        assert_eq(specs[2].value, "bar.*\\d")

        assert_eq(#specs, 2)
    end)

    it("exclude specifiers", function()
        local specs = filter.parse("!foo !/bar").specs
        assert_eq(specs[1].kind, filter.FilterKind.Simple)
        assert_eq(specs[1].exclude, true)
        assert_eq(specs[1].fixed_string, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filter.FilterKind.FileContents)
        assert_eq(specs[2].exclude, true)
        assert_eq(specs[2].fixed_string, false)
        assert_eq(specs[2].value, "bar")

        assert_eq(#specs, 2)
    end)

    it("rest-of-the-line (//) specifier for file contents", function()
        local specs = filter.parse("foo //a bb ccc").specs
        assert_eq(specs[1].kind, filter.FilterKind.Simple)
        assert_eq(specs[1].exclude, false)
        assert_eq(specs[1].fixed_string, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filter.FilterKind.FileContents)
        assert_eq(specs[2].exclude, false)
        assert_eq(specs[2].fixed_string, false)
        assert_eq(specs[2].value, "a bb ccc")

        assert_eq(#specs, 2)
    end)

    it("excluded // filters", function()
        local specs = filter.parse("foo !//a bb ccc").specs
        assert_eq(specs[1].kind, filter.FilterKind.Simple)
        assert_eq(specs[1].exclude, false)
        assert_eq(specs[1].fixed_string, false)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filter.FilterKind.FileContents)
        assert_eq(specs[2].exclude, true)
        assert_eq(specs[2].fixed_string, false)
        assert_eq(specs[2].value, "a bb ccc")

        assert_eq(#specs, 2)
    end)

    it("fixed-string specifiers", function()
        local specs = filter.parse("=foo =/bar !=/both").specs
        assert_eq(specs[1].kind, filter.FilterKind.Simple)
        assert_eq(specs[1].exclude, false)
        assert_eq(specs[1].fixed_string, true)
        assert_eq(specs[1].value, "foo")

        assert_eq(specs[2].kind, filter.FilterKind.FileContents)
        assert_eq(specs[2].exclude, false)
        assert_eq(specs[2].fixed_string, true)
        assert_eq(specs[2].value, "bar")

        assert_eq(specs[3].kind, filter.FilterKind.FileContents)
        assert_eq(specs[3].exclude, true)
        assert_eq(specs[3].fixed_string, true)
        assert_eq(specs[3].value, "both")

        assert_eq(#specs, 3)
    end)

    it("files-with-content filters", function()
        local specs = filter.parse("?red =?green !?blue !=?cyan").specs
        assert_eq(specs[1].kind, filter.FilterKind.FileNameWithContents)
        assert_eq(specs[1].exclude, false)
        assert_eq(specs[1].fixed_string, false)
        assert_eq(specs[1].value, "red")

        assert_eq(specs[2].kind, filter.FilterKind.FileNameWithContents)
        assert_eq(specs[2].exclude, false)
        assert_eq(specs[2].fixed_string, true)
        assert_eq(specs[2].value, "green")

        assert_eq(specs[3].kind, filter.FilterKind.FileNameWithContents)
        assert_eq(specs[3].exclude, true)
        assert_eq(specs[3].fixed_string, false)
        assert_eq(specs[3].value, "blue")

        assert_eq(specs[4].kind, filter.FilterKind.FileNameWithContents)
        assert_eq(specs[4].exclude, true)
        assert_eq(specs[4].fixed_string, true)
        assert_eq(specs[4].value, "cyan")

        assert_eq(#specs, 4)
    end)

    it("trailing backslash", function()
        local specs = filter.parse([[foo\ bar /aaa\ bbbb =/xy\ z\ 000 !?abc\]]).specs
        assert_eq(specs[1].kind, filter.FilterKind.Simple)
        assert_eq(specs[1].exclude, false)
        assert_eq(specs[1].fixed_string, false)
        assert_eq(specs[1].value, "foo bar")

        assert_eq(specs[2].kind, filter.FilterKind.FileContents)
        assert_eq(specs[2].exclude, false)
        assert_eq(specs[2].fixed_string, false)
        assert_eq(specs[2].value, "aaa bbbb")

        assert_eq(specs[3].kind, filter.FilterKind.FileContents)
        assert_eq(specs[3].exclude, false)
        assert_eq(specs[3].fixed_string, true)
        assert_eq(specs[3].value, "xy z 000")

        assert_eq(specs[4].kind, filter.FilterKind.FileNameWithContents)
        assert_eq(specs[4].exclude, true)
        assert_eq(specs[4].fixed_string, false)
        assert_eq(specs[4].value, "abc")

        assert_eq(#specs, 4)

        specs = filter.parse([[=abc\]]).specs
        assert_eq(specs[1].kind, filter.FilterKind.Simple)
        assert_eq(specs[1].exclude, false)
        assert_eq(specs[1].fixed_string, true)
        assert_eq(specs[1].value, "abc\\")

        assert_eq(#specs, 1)
    end)

    it("extract sources", function()
        local f = filter.parse("@foo bar")
        assert_eq("foo", f.source_name)
        assert_eq("bar", f.specs[1].value)

        f = filter.parse([[@foo:1\ 2 /bar]])
        assert_eq("foo", f.source_name)
        assert_eq("1 2", f.source_argument)
        assert_eq("bar", f.specs[1].value)
        assert_eq(filter.FilterKind.FileContents, f.specs[1].kind)
    end)
end)
