local Path = require("plenary.path")
local utils = require("telescope.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")

local get_grit_command = function(prompt, opts)
	local dry_run = { "--dry-run" }
	if opts.dangerously_run then
		dry_run = { "--force" }
	end
	local output = { "--output", opts.output or "compact" }
	local language = { "--language", opts.language or "js" }

	return vim.tbl_flatten({
		"grit",
		"apply",
		prompt,
		opts.cwd,
		dry_run,
		output,
		language,
	})
end

-- see telescope/make_entry.lua:80
local handle_entry_index = function(opts, t, k)
	local override = ((opts or {}).entry_index or {})[k]
	if not override then
		return
	end

	local val, save = override(t, opts)
	if save then
		rawset(t, k, val)
	end
	return val
end

-- see telescope/make_entry.lua:208
local lookup_keys = {
	value = 1,
	ordinal = 1,
}

-- see telescope/make_entry.lua:214
local parse = function(t)
	local _, _, filename, lnum, col, text = string.find(t.value, [[(..-):(%d+):(%d+) - (.*)]])

	local ok
	ok, lnum = pcall(tonumber, lnum)
	if not ok then
		lnum = nil
	end

	ok, col = pcall(tonumber, col)
	if not ok then
		col = nil
	end

	t.filename = filename
	t.lnum = lnum
	t.col = col
	t.text = text

	return { filename, lnum, col, text }
end

local get_grit_entry = function(opts)
	local opts = opts or {}

	-- see telescope/make_entry.lua:277
	local execute_keys = {
		path = function(t)
			if Path:new(t.filename):is_absolute() then
				return t.filename, false
			else
				return Path:new({ t.cwd, t.filename }):absolute(), false
			end
		end,

		filename = function(t)
			return parse(t)[1], true
		end,

		lnum = function(t)
			return parse(t)[2], true
		end,

		col = function(t)
			return parse(t)[3], true
		end,

		text = function(t)
			return parse(t)[4], true
		end,
	}

	local mt
	mt = {
		cwd = utils.path_expand(opts.cwd or vim.loop.cwd()),
		display = function(entry)
			local isReplacing = mt.text == "rewritten"
			if not isReplacing then
				return entry[1]
			end
			return "rewriting!!!"
		end,
		-- see telescope/make_entry.lua:342
		__index = function(t, k)
			local override = handle_entry_index(opts, t, k)
			if override then
				return override
			end

			local raw = rawget(mt, k)
			if raw then
				return raw
			end

			local executor = rawget(execute_keys, k)
			if executor then
				local val, save = executor(t)
				if save then
					rawset(t, k, val)
				end
				return val
			end

			return rawget(t, rawget(lookup_keys, k))
		end,
	}

	return function(line)
		if not line:match(" %- %a+$") then
			return
		end
		return setmetatable({ line }, mt)
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
		vim.notify(vim.inspect(get_grit_command(line, all_opts)))
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
			vim.notify(vim.inspect(entry))
			return actions._command(opts, { cwd = entry.filename, output = "standard" })
		end,
	})

	local match_previewer = function()
		local entry = action_state.get_selected_entry()
		if not entry or entry.text == "- matched" then
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
				map("i", "<c-space>", actions.apply_to_file(opts))
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
