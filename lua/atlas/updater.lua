local M = {}

local BufData = require("atlas.view.bufdata")
local DirectSearch = require("atlas.directsearch")
local Errors = require("atlas.view.errors")
local Filter = require("atlas.filter")
local Results = require("atlas.view.results")
local Runner = require("atlas.searchprogram.runner")
local SearchProgram = require("atlas.searchprogram")
local Sources = require("atlas.sources")
local Tree = require("atlas.view.tree")

---@return atlas.filter.Filter
local function parse_prompt(bufnr)
    local buflines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local input = table.concat(buflines, "\n")
    return Filter.parse(input)
end

---@param finder atlas.Finder
---@param result? atlas.searchprogram.ProgramOutput
local function render_results(finder, result)
    Errors.hide(finder)

    local columns_gap = finder.view.config.view.results.columns_gap
    local bufnr = finder.view.results_buffer

    finder.marks.items = {}
    finder.marks.all = false

    if result == nil then
        -- Empty results

        finder.items_index = {}
        vim.schedule(function()
            Results.set_content(bufnr, columns_gap, {}, {})
        end)

        return
    end

    local tree = Tree.build(result)
    local bufdata = BufData.render(finder.view.config, tree, finder.git_stats, result.max_line_number)

    finder.search_dir = result.search_dir
    finder.items_index = bufdata.items

    -- Save the results if we need to rebuild the view when Git changes are
    -- received.
    if finder.git_stats == nil then
        finder.state.updater_last_result = result
    end

    vim.schedule(function()
        local results = Results.set_content(bufnr, columns_gap, bufdata.lines, bufdata.items)

        -- Update folds
        vim.api.nvim_buf_call(finder.view.results_buffer, function()
            vim.cmd.normal { args = { "zx" }, bang = true }

            local row = results.row_select
            if row then
                vim.api.nvim_win_set_cursor(finder.view.results_window, { row, 0 })
            end
        end)
    end)
end

---@param finder atlas.Finder
local function process(finder)
    -- Compute the filter from the current input. If the input produces
    -- the same filter, no change is done.
    local filter = parse_prompt(finder.view.prompt_buffer)

    if vim.deep_equal(finder.state.last_filter, filter) then
        return
    end

    finder.state.last_filter = filter

    -- Assign a unique id to ignore results from previous runs, if they
    -- are received after the results from newer runs.
    local run_id = vim.loop.now()
    finder.state.last_run_id = run_id

    -- Interrupt previous program, if any.
    if finder.state.last_program then
        finder.state.last_program:interrupt()
        finder.state.last_program = nil
    end

    local source = nil
    if filter.source_name and filter.source_name ~= "" then
        source = Sources.run(finder, filter.source_name, filter.source_argument)
    end

    -- If the source returns a list of files, and there are no other filters,
    -- build the results directly from that list.
    if source and source.files and vim.tbl_isempty(filter.specs) then
        local items = {}
        for _, file in ipairs(source.files) do
            table.insert(items, { file = file })
        end

        ---@type atlas.searchprogram.ProgramOutput
        local results = {
            items = items,
            search_dir = source.search_dir,
            max_line_number = 0,
        }

        render_results(finder, results)
        return
    end

    -- If the source returns a list of items, use direct search.
    if source then
        local ds_output = DirectSearch.try_search(filter, source)
        if ds_output then
            render_results(finder, ds_output)
            return
        end
    end

    -- Run the new program.
    local config = finder.view.config
    local program = SearchProgram.build(filter.specs, config, source)
    local run = Runner.run(config, program, function(results)
        if finder.state.last_run_id == run_id then
            render_results(finder, results)
            finder.state.last_program = nil
        end
    end, function(stderr)
        if finder.state.last_run_id ~= run_id then
            return
        end

        finder.state.last_program = nil

        if stderr == "" then
            render_results(finder, nil)
            return
        end

        Errors.show(finder, stderr)
    end)

    finder.state.last_program = run
end

---@param finder atlas.Finder
function M.update(finder)
    if finder.state.update_wait_timer ~= nil then
        finder.state.update_wait_timer:stop()
    end

    finder.state.update_wait_timer = vim.defer_fn(function()
        finder.state.update_wait_timer = nil

        local _, err = pcall(process, finder)

        if err ~= nil then
            Errors.show(finder, tostring(err))
        end
    end, finder.view.config.search.update_wait_time)
end

---@param finder atlas.Finder
function M.interrupt(finder)
    local state = finder.state
    if state.update_wait_timer ~= nil then
        state.update_wait_timer:stop()
        state.update_wait_timer = nil
    end

    if state.last_program then
        state.last_program:interrupt()
        state.last_program = nil
    end
end

---@param finder atlas.Finder
---@param result atlas.impl.GitStats
function M.set_git_stats(finder, result)
    finder.git_stats = result

    local last_result = finder.state.updater_last_result
    if last_result then
        render_results(finder, last_result)
        finder.state.updater_last_result = nil
    end
end

return M
