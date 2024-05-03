#!/usr/bin/env -S nvim -l

-- This script executes the tests inside the `tests/specs` directory.
--
-- Command-line arguments can be used to filter which tests are executed.
-- For example, the following command only executes a test if its path
-- includes `foo` or `bar`:
--
-- ```
-- $ tests/run.lua foo bar
-- ```

local TOPLEVEL = vim.fn.system({ "git", "rev-parse", "--show-toplevel" }):sub(1, -2)
if vim.fn.isdirectory(TOPLEVEL) ~= 1 then
    error("Not a directory: " .. vim.inspect(TOPLEVEL))
end

local TESTS_INIT = TOPLEVEL .. "/tests/init.lua"

--- Executes a command and returns its exit code.
---
---@param command string[]
---@return integer|nil
local function spawn(command)
    -- Use an empty HOME/XDG to avoid using user configuration.
    local fakehome = vim.fn.tempname()
    vim.fn.mkdir(fakehome)

    local env = {
        HOME = fakehome,
        XDG_CONFIG_DIRS = fakehome,
    }

    local forward = function(_, data)
        io.stdout:write(table.concat(data, "\n"))
    end

    local job = vim.fn.jobstart(command, {
        on_stdout = forward,
        on_stderr = forward,
        stdin = "null",
        env = env,
    })

    local exitcodes = vim.fn.jobwait { job }
    return exitcodes[1]
end

--- Install a dependency from a Git repository.
---
---@param gituri string
---@param revision string
---@return string
local function get_dependency(gituri, revision)
    local cachedir = TOPLEVEL .. "/.cache"

    if vim.fn.isdirectory(cachedir) ~= 1 then
        vim.fn.mkdir(cachedir)
        vim.fn.writefile({}, cachedir .. "/CACHEDIR.TAG")
    end

    local target = string.format("%s/%s-%s", cachedir, gituri:gsub(".*/", ""), vim.fn.tr(revision, "/", "_"))

    if vim.fn.isdirectory(target .. "/.git") == 1 then
        return target
    end

    local gitclone = {
        "git",
        "-c",
        "advice.detachedHead=false",
        "clone",
        "--depth=1",
        "--branch=" .. revision,
        gituri,
        target,
    }

    assert(spawn(gitclone) == 0)

    return target
end

-- Plenary is used to run the tests.
local PLENARY_PATH = get_dependency("https://github.com/nvim-lua/plenary.nvim.git", "v0.1.4")

-- Find which `_spec` files must be executed.
--
-- If there are no filters, use `PlenaryBustedDirectory`.

local SPECS_DIR = TOPLEVEL .. "/tests/specs"

local SPEC_COMMANDS = {}

if _G.arg[1] == nil then
    SPEC_COMMANDS[1] = string.format(
        "PlenaryBustedDirectory %s { minimal_init = '%s', sequential = true }",
        vim.fn.fnameescape(SPECS_DIR),
        TESTS_INIT
    )
else
    for _, path in ipairs(vim.fn.glob(SPECS_DIR .. "/**/*_spec.lua", true, true)) do
        local relpath = vim.fn.fnamemodify(path, ":p")

        local found = false
        for _, filter in ipairs(_G.arg) do
            if relpath:find(filter, 1, true) then
                found = true
                break
            end
        end

        if found then
            table.insert(
                SPEC_COMMANDS,
                string.format("lua require('plenary.test_harness').test_file([[%s]], { sequential = true })", relpath)
            )
        end
    end
end

-- Execute tests.

local failed = false
for _, spec_command in ipairs(SPEC_COMMANDS) do
    local exitcode = spawn {
        "nvim",
        "--clean",
        "--headless",
        "-c",
        "set rtp+=" .. PLENARY_PATH,
        "-c",
        "source " .. vim.fn.fnameescape(TESTS_INIT),
        "-c",
        spec_command,
    }

    if exitcode ~= 0 then
        failed = true
    end
end

if failed then
    vim.cmd("1cq")
end
