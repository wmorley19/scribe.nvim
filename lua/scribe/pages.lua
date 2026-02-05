local M = {}
local utils = require("scribe.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local spaces = require("scribe.spaces")

-- ScribePages command: pick a space (favorites first), then show pages for that space
function M.list_pages()
	spaces.select_space_with_favorites(function(space)
		if space and space.key then
			M.show_pages_for_space(space.key)
		end
	end)
end

function M.show_pages_for_space(space_key)
	if type(space_key) ~= "string" then
		vim.notify("Error: space_key is " .. type(space_key), vim.log.levels.ERROR)
		return
	end

	utils.execute_cli({ "page", "search", "--space", space_key, "--all" }, function(result, err)
		if err then
			vim.notify("Failed to list pages: " .. err, vim.log.levels.ERROR)
			return
		end

		local pages
		if type(result) == "string" then
			-- Streaming output from Go CLI (id|title per line)
			pages = utils.parse_streaming_lines(result, "pages")
		else
			pages = result.results or result
		end
		if not pages or #pages == 0 then
			vim.notify("No pages found in space", vim.log.levels.INFO)
			return
		end

		pickers
			.new({}, {
				prompt_title = "Pages in " .. space_key,
				finder = finders.new_table({
					results = pages,
					entry_maker = function(entry)
						local title = entry.title or "Untitled"
						local version = (entry.version and entry.version.number) or 0
						return {
							value = entry,
							display = string.format("%s (v%d)", title, version),
							ordinal = title,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if selection and selection.value then
							M.open_page(selection.value)
						end
					end)
					return true
				end,
			})
			:find()
	end)
end

-- Open a page: pass full page object (with _links.webui) or table with id. Opens in browser.
function M.open_page(page_obj)
	if type(page_obj) == "string" then
		page_obj = { id = page_obj }
	end
	if not page_obj or not page_obj.id then
		return
	end
	local webui = (page_obj._links and page_obj._links.webui) or (page_obj._link and page_obj._link.webui)
	if not webui or webui == "" then
		-- Streamed entries only have id/title; build view URL from pageId
		webui = "/pages/viewpage.action?pageId=" .. page_obj.id
	end
	local url = utils.join_scribe_url(require("scribe").config.scribe_url, webui)
	if url and url ~= "" then
		local open_cmd = vim.fn.has("mac") == 1 and "open" or "xdg-open"
		vim.fn.system(string.format("%s '%s'", open_cmd, url))
	end
end

return M
