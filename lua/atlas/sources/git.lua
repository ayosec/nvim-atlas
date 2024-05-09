local M = {}

---@param finder atlas.Finder
---@param argument string|nil
---@param search_dir string
---@return atlas.sources.Response
function M.gitdiff(finder, argument, search_dir)
    local rev

    -- The source argument is used to use a specific revision
    -- to compare.

    if argument and argument ~= "" then
        if vim.startswith(argument, "~") then
            argument = "@" .. argument
        end

        rev = { argument }
    else
        rev = finder.view.config.files.git.diff_arguments
    end

    return {
        search_dir = search_dir,
        filelist_command = vim.list_extend(
            vim.list_extend({ "git", "diff", "--name-only", "-z" }, rev),
            { "--", search_dir }
        ),
    }
end

return M
