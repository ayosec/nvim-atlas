local M = {}

---@return atlas.sources.Response
function M.buffers()
    local files = {}
    for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local filename = vim.api.nvim_buf_get_name(bufnr)
            if vim.fn.filereadable(filename) == 1 then
                filename = filename:gsub("^/", "")
                table.insert(files, filename)
            end
        end
    end

    return {
        search_dir = "/",
        files = files,
    }
end

---@param search_dir string
---@return atlas.sources.Response
function M.marks(search_dir)
    ---@type atlas.searchprogram.ResultItem[]
    local items = {}

    if not vim.endswith(search_dir, "/") then
        search_dir = search_dir .. "/"
    end

    for _, mark in ipairs(vim.fn.getmarklist()) do
        local filename = mark.file
        if filename:find(search_dir, 1, true) == 1 then
            table.insert(items, {
                file = filename:sub(#search_dir + 1),
                line = mark.pos[2],
                text = mark.mark,
            })
        end
    end

    for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local filename = vim.api.nvim_buf_get_name(bufnr)
            if filename:find(search_dir, 1, true) == 1 then
                for _, mark in ipairs(vim.fn.getmarklist(bufnr)) do
                    table.insert(items, {
                        file = filename:sub(#search_dir + 1),
                        line = mark.pos[2],
                        text = mark.mark,
                    })
                end
            end
        end
    end

    return {
        search_dir = search_dir,
        items = items,
    }
end

return M
