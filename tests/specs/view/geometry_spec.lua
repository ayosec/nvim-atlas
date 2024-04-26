local Geometry = require("atlas.view.geometry")
local atlas = require("atlas")

---@diagnostic disable-next-line:undefined-field
local assert_eq = assert.are.same

describe("Geometry", function()
    it("compute height relative to the UI", function()
        local config = atlas.default_config()
        config.view.height = "10%"

        local geometry = Geometry.compute_ui_geometry(config)

        assert_eq(100, geometry.prompt.width)
        assert_eq(1, geometry.prompt.height)

        assert_eq(100, geometry.results.width)
        assert_eq(4, geometry.results.height)
    end)

    it("compute fixed height", function()
        local config = atlas.default_config()
        config.view.height = 30

        local geometry = Geometry.compute_ui_geometry(config)

        assert_eq(100, geometry.prompt.width)
        assert_eq(1, geometry.prompt.height)

        assert_eq(100, geometry.results.width)
        assert_eq(29, geometry.results.height)
    end)

    it("preview window", function()
        local padding = 4

        local config = atlas.default_config()
        config.view.height = 10
        config.files.previewer.window.padding = padding

        local geometry = Geometry.compute_ui_geometry(config)

        assert_eq(4, geometry.preview.col)
        assert_eq(4, geometry.preview.row)
        assert_eq(geometry.prompt.row - 1 - padding * 2, geometry.preview.height)
        assert_eq(100 - padding * 2, geometry.preview.width)
    end)
end)
