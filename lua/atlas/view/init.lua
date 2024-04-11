local M = {}

---@enum atlas.view.ItemKind
M.ItemKind = {
    Directory = "D",
    File = "F",
    ContentMatch = "M",
}

---@alias atlas.view.Tree table<string|integer, atlas.view.Item>

--- Items in the results view.
---
---@class atlas.view.Item
---@field kind atlas.view.ItemKind
---@field path string
---@field children atlas.view.Tree
---@field line? integer
---@field text? string

return M
