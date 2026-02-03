local M = {}
local utils = require("scribe.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

-- Get the plugin directory
local function get_plugin_dir()
	local source = debug.getinfo(1, "S").source
	if source:sub(1, 1) == "@" then
		source = source:sub(2)
	end
	-- Remove /lua/scribe/new.lua to get plugin root
	return vim.fn.fnamemodify(source, ":h:h:h")
end

-- Load template from file
local function load_template(template_path)
	if not template_path or template_path == "" then
		-- Use default template
		template_path = get_plugin_dir() .. "/templates/default.md"
	end

	-- Check if template file exists
	if vim.fn.filereadable(template_path) == 0 then
		vim.notify("Template file not found: " .. template_path, vim.log.levels.WARN)
		-- Return a minimal default template
		return "# {{TITLE}}\n\n## Overview\n\n<!-- Add content here -->\n"
	end

	-- Read template file
	local template_content = vim.fn.readfile(template_path)
	return table.concat(template_content, "\n")
end

-- Process template with variables
local function process_template(template, title)
	local date = os.date("%Y-%m-%d")
	local processed = template:gsub("{{TITLE}}", title or "Untitled Document")
	processed = processed:gsub("{{DATE}}", date)
	return processed
end

function M.create_new_doc()
	-- Get template path from config (optional)
	local config = require("scribe").config
	local template_path = config.template_path or ""

	-- Load template
	local template = load_template(template_path)

	-- Get document title
	local title = vim.fn.input("Document title: ", "")
	if title == "" then
		vim.notify("Title is required", vim.log.levels.ERROR)
		return
	end

	-- Process template
	local content = process_template(template, title)

	-- Create new buffer
	local buf = vim.api.nvim_create_buf(true, false)

	-- Set buffer name
	local filename = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower() .. ".md"
	vim.api.nvim_buf_set_name(buf, filename)

	-- Set content
	local lines = vim.split(content, "\n")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(buf, "modified", true)

	-- Switch to the new buffer
	vim.api.nvim_set_current_buf(buf)

	-- Move cursor to first placeholder or end of file
	local first_line = 0
	for i, line in ipairs(lines) do
		if line:match("<!--") or line:match("{{") then
			first_line = i - 1
			break
		end
	end
	vim.api.nvim_win_set_cursor(0, { first_line + 1, 0 })

	vim.notify("New document created from template!", vim.log.levels.INFO)
end

function M.create_new_doc_with_template()
	-- Get plugin directory
	local plugin_dir = get_plugin_dir()
	local templates_dir = plugin_dir .. "/templates"

	-- List available templates
	local templates = {}
	if vim.fn.isdirectory(templates_dir) == 1 then
		local files = vim.fn.readdir(templates_dir)
		for _, file in ipairs(files) do
			if file:match("%.md$") then
				table.insert(templates, {
					name = file:gsub("%.md$", ""),
					path = templates_dir .. "/" .. file,
				})
			end
		end
	end

	-- If no templates found, use default
	if #templates == 0 then
		table.insert(templates, {
			name = "default",
			path = templates_dir .. "/default.md",
		})
	end

	-- Let user select template
	pickers
		.new({}, {
			prompt_title = "Select Template",
			finder = finders.new_table({
				results = templates,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.name,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						M.create_doc_from_template(selection.value.path)
					end
				end)
				return true
			end,
		})
		:find()
end

function M.create_doc_from_template(template_path)
	-- Load template
	local template = load_template(template_path)

	-- Get document title
	local title = vim.fn.input("Document title: ", "")
	if title == "" then
		vim.notify("Title is required", vim.log.levels.ERROR)
		return
	end

	-- Process template
	local content = process_template(template, title)

	-- Create new buffer
	local buf = vim.api.nvim_create_buf(true, false)

	-- Set buffer name
	local filename = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower() .. ".md"
	vim.api.nvim_buf_set_name(buf, filename)

	-- Set content
	local lines = vim.split(content, "\n")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(buf, "modified", true)

	-- Switch to the new buffer
	vim.api.nvim_set_current_buf(buf)

	-- Move cursor to first placeholder or end of file
	local first_line = 0
	for i, line in ipairs(lines) do
		if line:match("<!--") or line:match("{{") then
			first_line = i - 1
			break
		end
	end
	vim.api.nvim_win_set_cursor(0, { first_line + 1, 0 })

	vim.notify("New document created from template!", vim.log.levels.INFO)
end

return M
