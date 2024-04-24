local M = {}

local BufData = require("atlas.view.bufdata")
local Errors = require("atlas.view.errors")
local Filter = require("atlas.filter")
local Pipeline = require("atlas.pipeline")
local Runner = require("atlas.pipeline.runner")
local Tree = require("atlas.view.tree")

---@return atlas.filter.Spec[]
local function parse_prompt(bufnr)
    local buflines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local input = table.concat(buflines, "\n")
    return Filter.parse(input)
end

---@param instance atlas.Instance
---@param result? atlas.pipeline.Result
local function render_results(instance, result)
    Errors.hide(instance)

    local bufnr = instance.view.results_buffer

    if result == nil then
        -- Empty results

        instance.items_index = {}
        vim.schedule(function()
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
        end)

        return
    end

    local tree = Tree.build(result)
    local bufdata = BufData.render(instance.view.config, tree, result.max_line_number)

    instance.items_index = bufdata.items

    vim.schedule(function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, bufdata.lines)
        vim.bo[bufnr].vartabstop = table.concat(bufdata.vartabstop, ",")

        -- Update folds
        vim.api.nvim_buf_call(instance.view.results_buffer, function()
            vim.cmd.normal { args = { "zx" }, bang = true }
        end)
    end)
end

---@param instance atlas.Instance
local function process(instance)
    -- Compute the filter from the current input. If the input produces
    -- the same filter, no change is done.
    local filter = parse_prompt(instance.view.prompt_buffer)

    if vim.deep_equal(instance.state.last_filter, filter) then
        return
    end

    instance.state.last_filter = filter

    -- Assign a unique id to ignore results from previous runs, if they
    -- are received after the results from newer runs.
    local run_id = os.time()
    instance.state.last_run_id = run_id

    -- Interrupt previous pipeline, if any.
    if instance.state.last_pipeline_run then
        instance.state.last_pipeline_run:interrupt()
    end

    -- Run the new pipeline.
    local config = instance.view.config
    local pipeline = Pipeline.build(filter, config)
    local run = Runner.run(config, pipeline, function(results)
        if instance.state.last_run_id == run_id then
            render_results(instance, results)
            instance.state.last_pipeline_run = nil
        end
    end, function(stderr)
        if instance.state.last_run_id ~= run_id then
            return
        end

        instance.state.last_pipeline_run = nil

        if stderr == "" then
            render_results(instance, nil)
            return
        end

        Errors.show(instance, stderr)
    end)

    instance.state.last_pipeline_run = run
end

---@param instance atlas.Instance
function M.update(instance)
    if instance.state.update_wait_timer ~= nil then
        instance.state.update_wait_timer:stop()
    end

    instance.state.update_wait_timer = vim.defer_fn(function()
        instance.state.update_wait_timer = nil

        local _, err = pcall(process, instance)

        if err ~= nil then
            Errors.show(instance, tostring(err))
        end
    end, instance.view.config.search.update_wait_time)
end

return M
