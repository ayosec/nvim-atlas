local M = {}

---@enum atlas.searchprogram.OutputKind
M.OutputKind = {
    FileNames = 1,
    JsonLines = 2,
}

--- Special command name to indicate that a pipeline must use a temporary
--- file as its input.
M.FIFOStdinMark = "\0 FIFOStdinMark"

--- Build a pipeline with `rg` commands from a specifiers list.
---
---@param specs atlas.filter.Spec[]
---@param config atlas.Config
---@return atlas.searchprogram.Program
function M.build(specs, config)
    return require("atlas.searchprogram.builder").build(specs, config)
end

return M
