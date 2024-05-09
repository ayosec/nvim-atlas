local Sources = require("atlas.sources")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

describe("Sources", function()
    it("find by prefixes", function()
        local finder = {
            view = {
                config = {
                    sources = {
                        abcdef = {
                            handler = function(req)
                                assert_eq("abcdef", req.source_name)
                                assert_eq("123", req.argument)

                                return {
                                    search_dir = ".",
                                    files = { "a", "b" },
                                }
                            end,
                        },
                    },
                },
            },
        }

        local response = Sources.run(finder, "abc", "123")
        assert_eq({ "a", "b" }, response.files)
    end)
end)
