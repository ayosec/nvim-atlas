local M = {}

local Buffer = require("string.buffer")

---@param output string
---@param code integer
---@param on_result fun(exitcode: integer, stats: atlas.impl.GitStats)
local function parse_output(output, code, on_result)
    local files = {}
    local max_added = 0
    local max_removed = 0

    for entry in vim.gsplit(output, "\0") do
        local s1 = entry:find("\t")
        local s2 = s1 and entry:find("\t", s1 + 2)

        if s2 then
            local added = tonumber(entry:sub(1, s1 - 1))
            local removed = tonumber(entry:sub(s1 + 1, s2 - 1))

            if added and removed then
                files[entry:sub(s2 + 1)] = {
                    added = added,
                    removed = removed,
                }

                if added and added > max_added then
                    max_added = added
                end

                if removed and removed > max_removed then
                    max_removed = removed
                end
            end
        end
    end

    ---@type atlas.impl.GitStats
    local result = {
        added_width = #tostring(max_added),
        removed_width = #tostring(max_removed),
        files = files,
    }

    vim.schedule(function()
        on_result(code, result)
    end)
end

---@class atlas.impl.GitStats
---@field added_width integer
---@field removed_width integer
---@field files table<string, { added: integer, removed: integer }>

---@param workdir string|nil
---@param git_command string
---@param diff_extra_args string[]
---@param on_result fun(exitcode: integer, stats: atlas.impl.GitStats)
function M.stats(workdir, git_command, diff_extra_args, on_result)
    local diff_args = vim.list_extend({ "diff", "--numstat", "-z" }, diff_extra_args)

    local stdout = vim.loop.new_pipe()
    assert(stdout)

    local spawn_args = {
        args = diff_args,
        hide = true,
        cwd = workdir,
        stdio = { nil, stdout },
    }

    local stdout_data = Buffer.new()

    local handle
    handle = vim.loop.spawn(git_command, spawn_args, function(code, _)
        parse_output(stdout_data:tostring(), code, on_result)

        if handle then
            handle:close()
        end
    end)

    stdout:read_start(function(err, data)
        assert(not err, err)

        if data then
            stdout_data:put(data)
        else
            stdout:close()
        end
    end)
end

return M
