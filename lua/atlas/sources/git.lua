local M = {}

---@param search_dir string
---@return string?
local function git_root(search_dir)
    local matches = vim.fs.find(".git", {
        path = search_dir,
        upward = true,
    })

    if #matches == 0 then
        return nil
    end

    return vim.fs.dirname(matches[1])
end

---@param finder atlas.Finder
---@param argument string|nil
---@param search_dir string
---@return atlas.sources.Response
function M.gitdiff(finder, argument, search_dir)
    local rev

    -- Run the command from the root directory of the repository.
    local root = git_root(search_dir)

    if not root then
        -- Empty list if `search_dir` is not a git repository.
        return {
            search_dir = search_dir,
            files = {},
        }
    end

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
        search_dir = root,
        filelist_command = vim.list_extend(
            vim.list_extend({ "git", "diff", "--name-only", "-z" }, rev),
            { "--", search_dir }
        ),
    }
end

return M
