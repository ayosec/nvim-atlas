local M = {}

local buffer = require("string.buffer")

---@class atlas.pipeline.StderrCollector
---@field fd_write integer
---@field handle_reader uv_pipe_t
---@field buffer string.buffer

---@class atlas.pipeline.StderrCollector
local StderrCollector = {}

--- Return the received data.
---
---@return string
function StderrCollector:get()
    return self.buffer:tostring()
end

--- Close the file descriptor for the write side. Expected to be
--- executed when all process sharing this stderr are running.
---
function StderrCollector:close_write()
    vim.loop.fs_close(self.fd_write)
    self.fd_write = -1000
end

---@return atlas.pipeline.StderrCollector
function M.collector()
    local pipes = vim.loop.pipe()
    assert(pipes)

    local output = buffer.new()

    local wrapper = vim.loop.new_pipe()
    assert(wrapper)

    local function reader(err, data)
        if err then
            output:putf("stderr reader failed: %s\n", vim.inspect(err))
        end

        if data then
            output:put(data)
        else
            wrapper:close()
        end
    end

    wrapper:open(pipes.read)
    wrapper:read_start(reader)

    local collector = {
        fd_write = pipes.write,
        handle_reader = wrapper,
        buffer = output,
    }

    return setmetatable(collector, { __index = StderrCollector })
end

return M
