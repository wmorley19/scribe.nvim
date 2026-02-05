local M = {}
-- ... other requires ...
local spaces = require("scribe.spaces")

function M.show_pages_for_space(space_key)
	-- Safety check: ensure space_key is a string
	if type(space_key) ~= "string" then
		vim.notify("Error: space_key is " .. type(space_key), vim.log.levels.ERROR)
		return
	end

	pickers
		.new({}, {
			prompt_title = "Pages in " .. space_key,
			finder = finders.new_job({ "scribe-cli", "page", "search", "--space", space_key, "--all" }, function(entry)
				local id, title = entry:match("([^|]+)|(.+)")
				if not id then
					return nil
				end
				return { value = id, display = title, ordinal = title }
			end),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)

					-- selection.value is the ID string from our finder
					if selection and selection.value then
						M.open_page(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

function M.open_page(page_id)
	if type(page_id) ~= "string" then
		vim.notify("Error: page_id is a " .. type(page_id), vim.log.levels.ERROR)
		return
	end
	vim.cmd("edit confluence://" .. page_id)
end

return M
