local M = {}

---@enum ResultsViewItemKind
M.ResultsViewItemKind = {
    Directory = "D",
    File = "F",
    ContentMatch = "M",
}

---@alias ResultsViewTree table<string|integer, ResultsViewItem>

--- Items in the results view.
---
---@class ResultsViewItem
---@field kind ResultsViewItemKind
---@field path string
---@field children ResultsViewTree
---@field line? integer
---@field text? string

return M
