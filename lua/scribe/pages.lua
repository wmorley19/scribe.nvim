local M = {}
local utils = require("scribe.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local spaces = require("scribe.spaces")

function M.list_pages()
	-- Favorites first, then option to search all spaces
	spaces.select_space_with_favorites(function(space)
		M.show_pages_for_space(space.key)
	end)
end

function M.show_pages_for_space(space_key)
	utils.execute_cli({ "page", "search", "--space", space_key }, function(result, err)
		if err then
			vim.notify("Failed to list pages: " .. err, vim.log.levels.ERROR)
			return
		end

		local pages = result.results or result
		if #pages == 0 then
			vim.notify("No pages found in space", vim.log.levels.INFO)
			return
		end

		pickers
			.new({}, {
				prompt_title = "Pages in Space: " .. space_key,
				finder = finders.new_table({
					results = pages,
					entry_maker = function(entry)
						local version = (entry.version and entry.version.number) or 0
						return {
							value = entry,
							display = string.format("%s (v%d)", entry.title or "Untitled", version),
							ordinal = entry.title or "Untitled",
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
			})
			:find()
	end)
end

return M
