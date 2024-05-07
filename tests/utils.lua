local utils = {}

local Buffer = require("string.buffer")

local islist = vim.islist or vim.tbl_islist

--- Check if all items from `items` are present in `target`
---
---@param target any[]
---@param items any[]
function utils.assert_list_contains(target, items)
    if not islist(target) then
        error("Expected a list, found " .. vim.inspect(target))
    end

    for _, item in ipairs(items) do
        local found = false
        for _, other in pairs(target) do
            if vim.deep_equal(item, other) then
                found = true
                break
            end
        end

        if not found then
            error("Missing " .. vim.inspect(item) .. " in " .. vim.inspect(target))
        end
    end
end

--- Simulate a one-shot channel to wait for a value in a background task.
---@generic T
---@return fun(T)
---@return fun(timeout?: integer):T
function utils.oneshot()
    local value = nil
    local received = false

    local tx = function(v)
        assert(not received)
        value = v
        received = true
    end

    local rx = function(timeout)
        vim.wait(timeout or 5000, function()
            return received
        end)

        if not received then
            error("Timeout")
        end

        return value
    end

    return tx, rx
end

--- Execute a program, and check that it completes successful.
---
---@param command string[]
---@param workdir string|nil
---@return string
function utils.run_command(command, workdir)
    local stdio = Buffer.new()

    local function read_io(_, data)
        stdio:put(table.concat(data, "\n"))
    end

    local job = vim.fn.jobstart(command, {
        cwd = workdir,
        stdin = "null",
        on_stdout = read_io,
        on_stderr = read_io,
    })

    assert(job > 0)

    local exitstatus = vim.fn.jobwait({ job })[1]
    local output = stdio:tostring()

    if exitstatus ~= 0 then
        vim.print("Output from " .. vim.inspect(command) .. ":\n--\n" .. output .. "--\n")
        error("Exit code: " .. exitstatus)
    end

    return output
end

return utils
