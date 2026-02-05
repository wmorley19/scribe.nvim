local M = {}
local utils = require("scribe.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local spaces = require("scribe.spaces")

function M.push_current_file()
	if not utils.is_markdown() then
		vim.notify("Current buffer is not a markdown file", vim.log.levels.ERROR)
		return
	end

	local file_path = utils.get_current_file()
	if file_path == "" then
		vim.notify("Please save the file first", vim.log.levels.ERROR)
		return
	end

	-- If file has Confluence frontmatter (e.g. from a previous pull), update existing page instead of creating new
	local frontmatter = utils.get_frontmatter()
	if frontmatter and frontmatter.confluence_page_id then
		require("scribe.update").update_current_file()
		return
	end

	-- No frontmatter: create a new page (select space, optional parent, title)
	spaces.select_space_with_favorites(function(space)
		if not space then
			return
		end

		-- Then let user select parent page (optional)
		M.select_parent_page(space.key, function(parent)
			local title = vim.fn.input("Page title: ", vim.fn.expand("%:t:r"))
			if title == "" then
				vim.notify("Title is required", vim.log.levels.ERROR)
				return
			end

			local args = {
				"page",
				"create",
				"--space",
				space.key,
				"--title",
				title,
				"--file",
				file_path,
			}

			if parent then
				table.insert(args, "--parent")
				table.insert(args, parent.id)
			end

			vim.notify("Pushing to Confluence...", vim.log.levels.INFO)

			utils.execute_cli(args, function(result, err)
				if err then
					vim.notify("Failed to push: " .. err, vim.log.levels.ERROR)
					return
				end

				vim.notify("Page created successfully!", vim.log.levels.INFO)

				-- Update frontmatter with page metadata
				utils.update_frontmatter({
					confluence_page_id = result.id,
					confluence_space = space.key,
					confluence_title = title,
				})

				-- Open in browser
				local webui = (result._links and result._links.webui) or (result._link and result._link.webui) or ""
				local url = utils.join_scribe_url(require("scribe").config.scribe_url, webui)
				if url and url ~= "" then
					local open_cmd = vim.fn.has("mac") == 1 and "open" or "xdg-open"
					vim.fn.system(string.format("%s '%s'", open_cmd, url))
				end
			end)
		end)
	end)
end

function M.select_parent_page(space_key, callback)
	local skip = vim.fn.input("Select parent page? (y/n): ", "n")
	if skip:lower() ~= "y" then
		callback(nil)
		return
	end

	utils.execute_cli({ "page", "search", "--space", space_key }, function(result, err)
		if err then
			vim.notify("Failed to list pages: " .. err, vim.log.levels.ERROR)
			callback(nil)
			return
		end

		local pages = result.results or result
		if not pages or #pages == 0 then
			vim.notify("No pages found in space", vim.log.levels.INFO)
			callback(nil)
			return
		end

		pickers
			.new({}, {
				prompt_title = "Select Parent Page (optional)",
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
