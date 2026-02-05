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
	pickers
		.new({}, {
			prompt_title = "Pages in Space: " .. space_key .. " (Streaming)",
			finder = finders.new_job(function()
				-- Calls your Go CLI with the new --all flag
				-- Command: scribe-cli page search --space SPACE_KEY --all
				return { "scribe-cli", "page", "search", "--space", space_key, "--all" }
			end, function(entry)
				-- Parses the "ID|TITLE" format from your Go fmt.Printf
				local id, title = entry:match("([^|]+)|(.+)")
				if not id then
					return nil
				end

				return {
					value = id,
					display = title,
					ordinal = title,
				}
			end),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)

					if not selection then
						return
					end
					if selection and selection.value then
						M.open_page(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

-- Helper to actually pull the content once a page is selected
function M.open_page(page_id)
	if type(page_id) ~= "string" then
		vim.notify("Error: page_id is not a string", vim.log.levels.ERROR)
		return
	end
	vim.cmd("edit confluence://" .. page_id)
	-- Your existing logic to populate the buffer with 'scribe-cli page get'
end

return M
