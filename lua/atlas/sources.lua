local M = {}

local MESSAGES_PREFIX = require("atlas.view.errors").MESSAGES_PREFIX

---@class atlas.sources.Request
---@field finder atlas.Finder
---@field source_name string
---@field argument? string

---@class atlas.sources.Response
---@field search_dir? string
---@field filelist_command? string[]
---@field files? string[]

---@alias atlas.sources.Handler fun(req: atlas.sources.Request): atlas.sources.Response

---@class atlas.sources.Source
---@field help? string
---@field handler atlas.sources.Handler

--- Register a new source to the default list.
---
---@param names string[]|string
---@param source atlas.sources.Source
function M.register(names, source)
    require("atlas").options.sources[names] = source
end

---@param finder atlas.Finder
---@param source_name string
---@return nil|string
---@return nil|atlas.sources.Source
local function find_by_name(finder, source_name)
    local candidates = {} ---@type {[1]: string, [2]: atlas.sources.Source}[]

    for names, source in pairs(finder.view.config.sources) do
        if type(names) == "string" then
            names = { names }
        end

        for _, name in pairs(names) do
            if name == source_name then
                -- Exact match. Ignore prefixes.
                return name, source
            end

            -- Track sources matching the prefix of the given name.
            if vim.startswith(name, source_name) then
                table.insert(candidates, { name, source })
            end
        end
    end

    -- If there is only one source with the prefix, use it.
    if #candidates == 1 then
        return candidates[1][1], candidates[1][2]
    end
end

---@param finder atlas.Finder
---@param source_name string
---@param source_argument? string
---@return atlas.sources.Response
function M.run(finder, source_name, source_argument)
    local found_name, source = find_by_name(finder, source_name)

    if not found_name or not source then
        error(MESSAGES_PREFIX .. "No source for " .. vim.inspect(source_name))
    end

    local response = source.handler {
        finder = finder,
        source_name = found_name,
        argument = source_argument,
    }

    return response
end

---@return table<string[], atlas.sources.Source[]>
function M.default_sources()
    local function get_oldfiles(cwd)
        local files = {}

        if cwd == "" or cwd:sub(-2, -2) ~= "/" then
            cwd = cwd .. "/"
        end

        for _, file in ipairs(vim.v.oldfiles) do
            if vim.startswith(file, cwd) and vim.fn.filereadable(file) == 1 then
                table.insert(files, file:sub(#cwd + 1))
            end
        end

        return {
            search_dir = cwd,
            files = files,
        }
    end

    local function get_search_dir(req)
        local search_dir = req.finder.view.config.files.search_dir
        return search_dir and search_dir() or vim.fn.getcwd()
    end

    return {
        [{ "b", "buffers" }] = {
            help = "Open buffers",
            handler = function(_)
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
            end,
        },

        [{ "g", "gitdiff" }] = {
            help = "Files with changes in a git repository.",
            handler = function(req)
                local cwd = get_search_dir(req)
                local rev

                -- The source argument is used to use a specific revision
                -- to compare.

                local argument = req.argument
                if argument and argument ~= "" then
                    if vim.startswith(argument, "~") then
                        argument = "@" .. argument
                    end

                    rev = { argument }
                else
                    rev = req.finder.view.config.files.git.diff_arguments
                end

                return {
                    search_dir = cwd,
                    filelist_command = vim.list_extend(
                        vim.list_extend({ "git", "diff", "--name-only", "-z" }, rev),
                        { "--", cwd }
                    ),
                }
            end,
        },

        [{ "G", "git" }] = {
            help = "Files tracked in a git repository.",
            handler = function(req)
                local cwd = get_search_dir(req)
                return {
                    search_dir = cwd,
                    filelist_command = { "git", "ls-files", "-z", cwd },
                }
            end,
        },

        [{ "o", "oldfiles" }] = {
            help = "Oldfiles in the current directory.",
            handler = function(req)
                return get_oldfiles(get_search_dir(req))
            end,
        },

        [{ "O", "alloldfiles" }] = {
            help = "Oldfiles in any directory.",
            handler = function(_)
                return get_oldfiles("")
            end,
        },
    }
end

return M
