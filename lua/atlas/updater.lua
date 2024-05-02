local M = {}

local BufData = require("atlas.view.bufdata")
local Errors = require("atlas.view.errors")
local Filter = require("atlas.filter")
local Pipeline = require("atlas.pipeline")
local Results = require("atlas.view.results")
local Runner = require("atlas.pipeline.runner")
local Tree = require("atlas.view.tree")

---@return atlas.filter.Spec[]
local function parse_prompt(bufnr)
    local buflines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local input = table.concat(buflines, "\n")
    return Filter.parse(input)
end

---@param finder atlas.Finder
---@param result? atlas.pipeline.Result
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
    local run_id = os.time()
    finder.state.last_run_id = run_id

    -- Interrupt previous pipeline, if any.
    if finder.state.last_pipeline_run then
        finder.state.last_pipeline_run:interrupt()
    end

    -- Run the new pipeline.
    local config = finder.view.config
    local pipeline = Pipeline.build(filter, config)
    local run = Runner.run(config, pipeline, function(results)
        if finder.state.last_run_id == run_id then
            render_results(finder, results)
            finder.state.last_pipeline_run = nil
        end
    end, function(stderr)
        if finder.state.last_run_id ~= run_id then
            return
        end

        finder.state.last_pipeline_run = nil

        if stderr == "" then
            render_results(finder, nil)
            return
        end

        Errors.show(finder, stderr)
    end)

    finder.state.last_pipeline_run = run
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

    if state.last_pipeline_run then
        state.last_pipeline_run:interrupt()
        state.last_pipeline_run = nil
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
