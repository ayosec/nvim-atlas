local M = {}

---@param search_dir string
function M.get_oldfiles(search_dir)
    local files = {}

    if search_dir == "" or not vim.endswith(search_dir, "/") then
        search_dir = search_dir .. "/"
    end

    for _, file in ipairs(vim.v.oldfiles) do
        if vim.startswith(file, search_dir) and vim.fn.filereadable(file) == 1 then
            table.insert(files, file:sub(#search_dir + 1))
        end
    end

    return {
        search_dir = search_dir,
        files = files,
    }
end

return M
