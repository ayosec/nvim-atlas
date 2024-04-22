local M = {}

local NS = vim.api.nvim_create_namespace("Atlas/ErrorMessages")

---@param instance atlas.Instance
---@param message string
function M.show(instance, message)
    vim.schedule(function()
        local bufnr = instance.view.results_buffer

        -- Compute window size.
        local width = 0
        local height = 0
        local text = { { { "", "ErrorMsg", 0 } } }

        for line in vim.gsplit(message, "\n", { trimempty = true }) do
            line = string.format("  %s  ", line)

            height = height + 1

            local row_width = vim.api.nvim_strwidth(line)
            if row_width > width then
                width = row_width
            end

            table.insert(text, { { line, "ErrorMsg", row_width } })
        end

        table.insert(text, { { "", "ErrorMsg", 0 } })
        table.insert(text, { { "", "Normal", 0 } })

        -- Add padding to imitate a box.
        for _, line in pairs(text) do
            local pad = width - table.remove(line[1], 3)
            if pad > 0 then
                line[1][1] = line[1][1] .. string.rep(" ", pad)
            end
        end

        -- Force an empty line at the beginning of the results buffer. This is
        -- needed because `nvim_buf_set_extmark` does not allow adding virt_lines
        -- before the first row.
        local first_result = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
        if first_result[1] ~= "" then
            vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })
        end

        vim.api.nvim_buf_set_extmark(bufnr, NS, 0, 0, {
            id = 1,
            hl_group = "ErrorMsg",
            hl_eol = true,
            virt_lines = text,
            virt_lines_leftcol = true,
        })
    end)
end

---@param instance atlas.Instance
function M.hide(instance)
    vim.schedule(function()
        vim.api.nvim_buf_clear_namespace(instance.view.results_buffer, NS, 0, -1)
    end)
end

return M
