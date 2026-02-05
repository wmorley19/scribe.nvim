local M = {}
local utils = require("scribe.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local spaces = require("scribe.spaces")

function M.pull_page()
	-- Favorites first, then option to search all spaces
	spaces.select_space_with_favorites(function(space)
		if not space then
			return
		end

		-- Then select page
		M.select_page(space.key, function(page)
			if not page then
				return
			end

			vim.notify("Fetching page content...", vim.log.levels.INFO)

			utils.execute_cli({
				"page",
				"get",
				"--id",
				page.id,
			}, function(result, err)
				if err then
					vim.notify("Failed to fetch page: " .. err, vim.log.levels.ERROR)
					return
				end

				-- Build filename from page title
				local filename = page.title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower() .. ".md"
				if filename == ".md" then
					filename = "page-" .. page.id .. ".md"
				end

				-- Get target directory: use current file's directory if available, else cwd
				local target_dir = vim.fn.expand("%:p:h")
				if target_dir == "" or target_dir == "." then
					target_dir = vim.fn.getcwd()
				end
				local filepath = target_dir .. "/" .. filename

				-- Build content with frontmatter
				local frontmatter = {
					"---",
					string.format("confluence_page_id: %s", page.id),
					string.format("confluence_space: %s", space.key),
					string.format("confluence_title: %s", page.title),
					"---",
					"",
				}
				local content_lines = vim.split(result, "\n")
				local all_lines = vim.list_extend(frontmatter, content_lines)

				-- Write to file in current directory
				local write_err = vim.fn.writefile(all_lines, filepath)
				if write_err ~= 0 then
					vim.notify("Failed to write file: " .. filepath, vim.log.levels.ERROR)
					return
				end

				-- Open the file in a buffer
				vim.cmd("edit " .. vim.fn.fnameescape(filepath))

				vim.notify("Page pulled to " .. filepath, vim.log.levels.INFO)
			end)
		end)
	end)
end

function M.select_page(space_key, callback)
	utils.execute_cli({ "page", "search", "--space", space_key, "--all" }, function(result, err)
		if err then
			vim.notify("Failed to list pages: " .. err, vim.log.levels.ERROR)
			return
		end

		local pages
		if type(result) == "string" then
			pages = utils.parse_streaming_lines(result, "pages")
		else
			pages = result.results or result
		end
		if not pages or #pages == 0 then
			vim.notify("No pages found in space", vim.log.levels.INFO)
			callback(nil)
			return
		end

		pickers
			.new({}, {
				prompt_title = "Select Page to Pull",
				finder = finders.new_table({
					results = pages,
					entry_maker = function(entry)
						return {
							value = entry,
							display = entry.title,
							ordinal = entry.title,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if selection and selection.value then
							callback(selection.value)
						end
					end)
					return true
				end,
			})
			:find()
	end)
end

return M
