local utils = require("telescope.utils")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")

local async_job = require("telescope._")
local LinesPipe = require("telescope._").LinesPipe

local make_entry = require("telescope.make_entry")
local log = require("telescope.log")

-- see telescope/finders/async_job_finder (7d1698f3d88b)
local async_job_finder = function(opts)
	log.trace("Creating async_job:", opts)
	local entry_maker = opts.entry_maker or make_entry.gen_from_string(opts)

	local fn_command = function(prompt)
		local command_list = opts.command_generator(prompt)
		if command_list == nil then
			return nil
		end

		local command = table.remove(command_list, 1)

		local res = {
			command = command,
			args = command_list,
		}

		return res
	end

	local job

	local callable = function(_, prompt, process_result, process_complete)
		if job then
			job:close(true)
		end

		local job_opts = fn_command(prompt)
		if not job_opts then
			process_complete()
			return
		end

		local writer = nil
		-- if job_opts.writer and Job.is_job(job_opts.writer) then
		--   writer = job_opts.writer
		if opts.writer then
			error("async_job_finder.writer is not yet implemented")
			writer = async_job.writer(opts.writer)
		end

		local stdout = LinesPipe()

		job = async_job.spawn({
			command = job_opts.command,
			args = job_opts.args,
			cwd = job_opts.cwd or opts.cwd,
			env = job_opts.env or opts.env,
			writer = writer,

			stdout = stdout,
		})

		local line_num = 0
		for line in stdout:iter(true) do
			local data = vim.json.decode(line)
			if not data then
				goto continue
			end

			local type_name = data.__typename
			if type_name == "Rewrite" then
				data = data.original
			end

			local source_file = data.sourceFile
			if type(source_file) ~= "string" then
				goto continue
			end

			local ranges = data.ranges
			if type(ranges) ~= "table" then
				goto continue
			end

			for _, range in pairs(ranges) do
				line_num = line_num + 1
				local entry = entry_maker({ source_file = source_file, range = range, type_name = type_name })
				if entry then
					entry.index = line_num
				end
				if process_result(entry) then
					return
				end
			end
			::continue::
		end

		process_complete()
	end

	return setmetatable({
		close = function()
			if job then
				job:close(true)
			end
		end,
	}, {
		__call = callable,
	})
end

local finders = {}

-- see telescope/finders:176 (7d1698f3d88b)
finders.new_job = function(command_generator, entry_maker, _, cwd)
	return async_job_finder({
		command_generator = command_generator,
		entry_maker = entry_maker,
		cwd = cwd,
	})
end

local get_grit_command = function(prompt, opts)
	local dry_run = { "--dry-run" }
	if opts.dangerously_run then
		dry_run = { "--force" }
	end
	local output = {}
	local language = { "--language", opts.language or "js" }

	local format = { "--jsonl" }
	if opts.pretty then
		output = { "--output", opts.output or "compact" }
		format = {}
	end

	local only_in_json = {}
	if opts.only_in_json then
		only_in_json = { "--only-in-json", "<", "echo", opts.only_in_json }
	end

	return vim.tbl_flatten({
		"grit",
		"apply",
		prompt,
		opts.cwd,
		dry_run,
		output,
		language,
		format,
		only_in_json,
	})
end

local get_only_in_json = function(entry)
	return '[{ "filePath": "'
		.. entry.path
		.. '", "messages": [{ "line": '
		.. entry.lnum
		.. ', "column": '
		.. entry.col
		.. ', "endLine": '
		.. entry.lnend
		.. ', "endColumn": '
		.. entry.colend
		.. " }] }]"
end

local get_grit_entry = function(opts)
	local mt
	mt = {
		cwd = utils.path_expand(opts.cwd or vim.loop.cwd()),
	}

	return function(line)
		local source_file = line.source_file
		local range = line.range
		local value = source_file .. ":" .. range.start.line .. ":" .. range.start.column

		local entry = {
			path = line.source_file,
			lnum = line.range.start.line,
			col = line.range.start.column,
			lnend = line.range["end"].line,
			colend = line.range["end"].column,
			text = line.type_name,
			value = line.source_file,
			ordinal = line.source_file,
			display = value .. " - " .. line.type_name,
			valid = true,
		}
		return setmetatable(entry, mt)
	end
end

local actions
actions = {
	_command = function(opts, action_opts)
		local all_opts = {}
		for k, v in pairs(opts) do
			all_opts[k] = v
		end
		for k, v in pairs(action_opts) do
			all_opts[k] = v
		end
		-- NOTE: Doesn't work when switching between previewers while typing
		-- https://github.com/nvim-telescope/telescope.nvim/issues/3051
		local line = action_state.get_current_line()
		return get_grit_command(line, all_opts)
	end,
	_action = function(opts, action_opts)
		vim.fn.jobstart(actions._command(opts, action_opts), {
			cwd = opts.cwd,
			on_exit = function()
				vim.notify("Applied grit pattern to " .. (action_opts.cwd or opts.cwd), vim.log.levels.INFO)
			end,
			on_stderr = function(_, data)
				if data[0] == "" and #data == 1 then
					return
				end
				vim.notify("Could not apply grit pattern: " .. vim.inspect(data), vim.log.levels.ERROR)
			end,
		})
	end,

	apply_to_entry = function(opts)
		return function()
			local entry = action_state.get_selected_entry()
			if entry == nil then
				return
			end
			actions._action(opts, {
				dangerously_run = true,
				only_in_json = get_only_in_json(entry),
			})
		end
	end,

	apply_to_file = function(opts)
		return function()
			local entry = action_state.get_selected_entry()
			if entry == nil then
				return
			end
			actions._action(opts, { dangerously_run = true, cwd = entry.filename })
		end
	end,

	apply_to_all = function(opts)
		return function()
			actions._action(opts, { dangerously_run = true })
		end
	end,
}

-- The previewer switches between grep and terminal depending on the action of the pattern
local previewer = function(opts)
	local grep_previewer = conf.grep_previewer(opts)
	local term_previewer = previewers.new_termopen_previewer({
		get_command = function(entry)
			return actions._command(
				opts,
				{ cwd = entry.filename, output = "standard", pretty = "true", only_in_json = get_only_in_json(entry) }
			)
		end,
	})

	local match_previewer = function()
		local entry = action_state.get_selected_entry()
		if not entry or entry.text == "Match" then
			return grep_previewer
		else
			return term_previewer
		end
	end

	local mt = {
		preview = function(...)
			match_previewer().preview(...)
		end,
		preview_fn = function(...)
			match_previewer().preview_fn(...)
		end,
		teardown = function(...)
			grep_previewer.teardown(...)
			term_previewer.teardown(...)
		end,
		title = function()
			return "Live GritQL Preview"
		end,
		send_input = function(...)
			match_previewer().send_input(...)
		end,
		scroll_fn = function(...)
			match_previewer().scroll_fn(...)
		end,
		scroll_horizontal_fn = function(...)
			match_previewer().scroll_horizontal_fn(...)
		end,
	}
	return mt
end

local function grit(opts)
	opts = opts or {}
	opts.cwd = opts.cwd or vim.loop.cwd()

	local live_grit = finders.new_job(function(prompt)
		if not prompt or prompt == "" then
			return nil
		end
		return get_grit_command(prompt, opts)
	end, opts.entry_maker or get_grit_entry(opts), opts.max_results, opts.cwd)
	pickers
		.new(opts, {
			prompt_title = "Live GritQL Search",
			finder = live_grit,
			previewer = previewer(opts),
			attach_mappings = function(_, map)
				map("i", "<c-space>", actions.apply_to_entry(opts))
				map("i", "<c-f>", actions.apply_to_file(opts))
				map("i", "<c-a>", actions.apply_to_all(opts))
				return true
			end,
		})
		:find()
end

grit()
return require("telescope").register_extension({
	exports = {
		grit = grit,
	},
})
