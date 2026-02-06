local M = {}
local utils = require("scribe.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local spaces = require("scribe.spaces")

function M.list_pages()
	spaces.select_space_with_favorites(function(space)
		M.show_pages_for_space(space.key)
	end)
end

function M.show_pages_for_space(space_key, offset)
	offset = offset or 0
	local limit = 50

	vim.notify(string.format("Fetching pages %d-%d...", offset + 1, offset + limit), vim.log.levels.INFO)
	utils.execute_cli(
		{ "page", "search", "--space", space_key, "--limit", tostring(limit), "--offset", tostring(offset) },
		function(result, err)
			if err then
				vim.notify("Failed to list pages: " .. err, vim.log.levels.ERROR)
				return
			end

			local pages = result.results or result
			if type(pages) ~= "table" then
				pages = {}
			end
			if #pages == 0 then
				vim.notify("No pages found in space", vim.log.levels.INFO)
				return
			end
			if #pages >= limit then
				table.insert(pages, {
					name = "➡️  Next Page...",
					action = "next_page",
					type = "system",
				})
			end

			-- Capture for closures
			local current_offset = offset
			local current_limit = limit
			local current_space_key = space_key

			pickers
				.new({}, {
					prompt_title = "Pages in " .. current_space_key,
					finder = finders.new_table({
						results = pages,
						entry_maker = function(entry)
							if entry.action == "next_page" then
								return {
									value = entry,
									display = entry.name,
									ordinal = "zzzz",
								}
							end
							local version = (entry.version and entry.version.number) or 0
							return {
								value = entry,
								display = string.format("%s (v%d)", entry.title or "Untitled", version),
								ordinal = entry.title or "Untitled",
							}
						end,
					}),
					sorter = conf.generic_sorter({}),
					attach_mappings = function(prompt_bufnr, map)
						actions.select_default:replace(function()
							local selection = action_state.get_selected_entry()
							actions.close(prompt_bufnr)
							if not selection or not selection.value then
								return
							end
							if selection.value.action == "next_page" then
								M.show_pages_for_space(current_space_key, current_offset + current_limit)
							elseif selection.value.id or selection.value.title then
								-- It's a page: add space to recent, then open the page
								utils.save_favorites({ key = current_space_key })
								M.open_page(selection.value)
							end
						end)

						-- Alt-a: add current space to recent (favorites) without opening a page
						map("i", "<A-a>", function()
							utils.save_favorites({ key = current_space_key })
							vim.notify("Space " .. current_space_key .. " added to recent", vim.log.levels.INFO)
						end)

						return true
					end,
				})
				:find()
		end
	)
end

-- Open a page in the browser. page_obj can have _links.webui or id (and optionally title).
function M.open_page(page_obj)
	if type(page_obj) == "string" then
		page_obj = { id = page_obj }
	end
	if not page_obj or not page_obj.id then
		return
	end
	local webui = (page_obj._links and page_obj._links.webui) or (page_obj._link and page_obj._link.webui)
	if not webui or webui == "" then
		webui = "/pages/viewpage.action?pageId=" .. page_obj.id
	end
	local config = require("scribe").config
	local url = utils.join_scribe_url(config.scribe_url, webui)
	if url and url ~= "" then
		local open_cmd = vim.fn.has("mac") == 1 and "open" or "xdg-open"
		vim.fn.system(string.format("%s '%s'", open_cmd, url))
	end
end

return M
