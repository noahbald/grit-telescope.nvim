local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local get_grit_command = function(prompt, opts)
	return vim.tbl_flatten({
		"grit",
		"apply",
		prompt,
		opts.cwd or vim.fn.getcwd(),
		"--dry-run",
		"--output",
		"compact",
		"--language",
		opts.language or "js",
	})
end

--- @param entry string
local get_grit_entry = function(entry)
	if not entry:match(" %- %a+$") then
		return
	end
	local value = entry:gsub(" %- %a+$", "")
	local path = value:gsub(":%d+:%d+$", "")
	return {
		value = value,
		display = entry,
		ordinal = path,
	}
end

local function grit(opts)
	opts = opts or {}

	local previewer = conf.grep_previewer(opts)
	local live_grit = finders.new_job(function(prompt)
		if not prompt or prompt == "" then
			return nil
		end
		return get_grit_command(prompt, opts)
	end, get_grit_entry, nil, opts.cwd)
	pickers
		.new(opts, {
			title = "Live GritQL Search",
			finder = live_grit,
			previewer = previewer,
		})
		:find()
end

grit()
return require("telescope").register_extension({
	exports = {
		grit = grit,
	},
})
