local M = {}

-- Max size, in bytes, to read an unloaded file.
local MAX_UNLOADED_FILE_SIZE = 256 * 1024

---@return table<string, integer>
local function load_bufnames()
    local bufnames = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        bufnames[vim.api.nvim_buf_get_name(bufnr)] = bufnr
    end

    return bufnames
end

--- Build a source with the references to the symbol under the cursor.
---
---@param callback fun(source: atlas.sources.Response)
function M.references_source(callback)
    local window = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_get_current_buf()

    local params = vim.lsp.util.make_position_params(window)
    params.context = { includeDeclaration = true }

    vim.lsp.buf_request(bufnr, "textDocument/references", params, function(err, result, _, _)
        if err then
            vim.notify("Failed to get LSP references: " .. vim.inspect(err), vim.log.levels.ERROR)
            return
        end

        if not result then
            return
        end

        local cwd = vim.fn.getcwd() .. "/"
        local all_in_cwd = true

        local bufnames = load_bufnames()

        ---@type table<string, table<integer, atlas.searchprogram.ResultItem>>
        local missing_text_fields = {}

        ---@type table<string, atlas.searchprogram.ResultItem>
        local refs = {}

        for _, item in ipairs(result) do
            local text
            local filename = vim.uri_to_fname(item.uri)

            local item_bufnr = bufnames[filename]
            if item_bufnr then
                local lnum = item.range.start.line
                local lines = vim.api.nvim_buf_get_lines(item_bufnr, lnum, lnum + 1, false)

                text = lines[1]
            end

            -- If multiple references appear in the same line, they will be
            -- merged in the `highlights` list.

            local line = item.range.start.line + 1
            local ref_key = string.format("%s#%d", filename, line)

            local ref_item = refs[ref_key]
            if not ref_item then
                ---@type atlas.searchprogram.ResultItem
                ref_item = {
                    file = filename,
                    line = line,
                    text = text,
                    highlights = {},
                }

                refs[ref_key] = ref_item

                if line and not text then
                    -- Store the missing text field, so the files can be read
                    -- when the final list is built.
                    local mtf = missing_text_fields[filename]
                    if not mtf then
                        if
                            vim.fn.filereadable(filename) == 1
                            and vim.fn.getfsize(filename) < MAX_UNLOADED_FILE_SIZE
                        then
                            mtf = {}
                            missing_text_fields[filename] = mtf
                        end
                    end

                    if mtf then
                        mtf[line] = ref_item
                    end
                end
            end

            -- If the range is in the same line, add it to the highlights.
            local range = item.range
            if range.start.line == range["end"].line then
                table.insert(ref_item.highlights, { range.start.character, range["end"].character })
            end

            -- Track if all filenames are under the current directory.
            if all_in_cwd and not vim.startswith(filename, cwd) then
                all_in_cwd = false
            end
        end

        -- Build the final list.
        local search_dir = all_in_cwd and cwd or "/"

        local items = {}
        for _, ref_item in pairs(refs) do
            ref_item.file = ref_item.file:sub(#search_dir + 1)
            table.insert(items, ref_item)
        end

        -- Add the missing text fields.
        for filename, lines in pairs(missing_text_fields) do
            local ok, fd = pcall(io.open, filename, "r")
            if ok and fd then
                local lnum = 0
                for text in fd:lines() do
                    lnum = lnum + 1
                    local item = lines[lnum]
                    if item then
                        item.text = text
                        lines[lnum] = nil

                        if vim.tbl_isempty(lines) then
                            vim.print("close after " .. lnum)
                            break
                        end
                    end
                end

                fd:close()
            end
        end

        callback {
            search_dir = search_dir,
            items = items,
        }
    end)
end

--- Creates a finder with LSP references.
---
---@param config? atlas.Config
function M.find_references(config)
    M.references_source(function(source)
        require("atlas").find {
            initial_prompt = "",
            default_source = source,
            config = config,
        }
    end)
end

return M
