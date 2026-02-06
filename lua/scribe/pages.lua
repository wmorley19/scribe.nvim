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
		if not space or not space.key then
			return
		end
		M.show_pages_picker(space.key)
	end)
end

-- Show picker: favorite/recent pages for this space first, then "Search / Browse..." option.
function M.show_pages_picker(space_key)
	if not space_key or type(space_key) ~= "string" then
		vim.notify("Pages: invalid space key", vim.log.levels.ERROR)
		return
	end
	local saved = utils.get_pages_for_space(space_key)
	local results = {}
	if type(saved) == "table" then
		for _, p in ipairs(saved) do
			if p and (p.id or p.title) then
				table.insert(results, p)
			end
		end
	end
	table.insert(results, {
		action = "search",
		name = "🔍 Search / Browse all pages...",
		ordinal = "zzzz",
	})

	if #results == 1 then
		-- Only "Search..." - go straight to query prompt
		M.prompt_then_show_pages(space_key)
		return
	end

	pickers
		.new({}, {
			prompt_title = "Pages in " .. space_key,
			finder = finders.new_table({
				results = results,
				entry_maker = function(entry)
					if not entry or type(entry) ~= "table" then
						return { value = {}, display = "?", ordinal = "?" }
					end
					if entry.action == "search" then
						return {
							value = entry,
							display = entry.name or "🔍 Search / Browse all pages...",
							ordinal = "zzzz",
						}
					end
					return {
						value = entry,
						display = "⭐ " .. (entry.title or "Untitled"),
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
					if selection.value.action == "search" then
						M.prompt_then_show_pages(space_key)
					elseif selection.value.id then
						utils.save_recent_page(selection.value, space_key)
						M.open_page(selection.value)
					end
				end)
				-- Alt-a: add selected page to favorites (if it's a page)
				map("i", "<A-a>", function()
					local selection = action_state.get_selected_entry()
					if selection and selection.value and selection.value.id then
						utils.add_page_favorite(selection.value, space_key)
						vim.notify("Page added to favorites", vim.log.levels.INFO)
					end
				end)
				return true
			end,
		})
		:find()
end

-- Prompt for query (Enter = blank = all pages), then show paginated list.
function M.prompt_then_show_pages(space_key)
	local query = vim.fn.input("Query (Enter = all pages): ")
	if query == nil then
		query = ""
	end
	query = vim.trim(query)
	M.show_pages_for_space(space_key, 0, query)
end

function M.show_pages_for_space(space_key, offset, query)
	offset = offset or 0
	query = query or ""
	local limit = 100

	local args = {
		"page", "search", "--space", space_key,
		"--query", query,
		"--limit", tostring(limit),
		"--offset", tostring(offset),
	}

	vim.notify(string.format("Fetching pages %d-%d...", offset + 1, offset + limit), vim.log.levels.INFO)
	utils.execute_cli(args, function(result, err)
		if err then
			vim.notify("Failed to list pages: " .. err, vim.log.levels.ERROR)
			return
		end
		if not result then
			vim.notify("No response from CLI", vim.log.levels.ERROR)
			return
		end

		local pages = (result.results and type(result.results) == "table" and result.results) or (type(result) == "table" and result) or {}
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

		local current_offset = offset
		local current_limit = limit
		local current_space_key = space_key
		local current_query = query

		pickers
			.new({}, {
				prompt_title = "Pages in " .. current_space_key,
				finder = finders.new_table({
					results = pages,
					entry_maker = function(entry)
						if not entry or type(entry) ~= "table" then
							return { value = {}, display = "?", ordinal = "?" }
						end
						if entry.action == "next_page" then
							return {
								value = entry,
								display = entry.name or "➡️  Next Page...",
								ordinal = "zzzz",
							}
						end
						local version = (entry.version and type(entry.version) == "table" and entry.version.number) or 0
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
							M.show_pages_for_space(current_space_key, current_offset + current_limit, current_query)
						elseif selection.value.id or selection.value.title then
							utils.save_favorites({ key = current_space_key })
							utils.save_recent_page(selection.value, current_space_key)
							M.open_page(selection.value)
						end
					end)

					map("i", "<A-a>", function()
						local selection = action_state.get_selected_entry()
						if selection and selection.value and (selection.value.id or selection.value.title) then
							utils.add_page_favorite(selection.value, current_space_key)
							vim.notify("Page added to favorites", vim.log.levels.INFO)
						else
							utils.save_favorites({ key = current_space_key })
							vim.notify("Space " .. current_space_key .. " added to recent", vim.log.levels.INFO)
						end
					end)

					return true
				end,
			})
			:find()
	end)
end

-- Open a page in the browser. page_obj can have _links.webui or id (and optionally title).
function M.open_page(page_obj)
	if type(page_obj) == "string" then
		page_obj = { id = page_obj }
	end
	if not page_obj or not page_obj.id then
		return
	end
	local webui = (page_obj._links and type(page_obj._links) == "table" and page_obj._links.webui)
		or (page_obj._link and type(page_obj._link) == "table" and page_obj._link.webui)
	if not webui or webui == "" then
		webui = "/pages/viewpage.action?pageId=" .. tostring(page_obj.id)
	end
	local config = require("scribe").config
	if not config then
		vim.notify("Scribe config not found", vim.log.levels.ERROR)
		return
	end
	local url = utils.join_scribe_url(config.scribe_url, webui)
	if url and url ~= "" then
		local open_cmd = vim.fn.has("mac") == 1 and "open" or "xdg-open"
		vim.fn.system(string.format("%s '%s'", open_cmd, url))
	end
end

return M
