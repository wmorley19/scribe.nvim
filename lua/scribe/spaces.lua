local M = {}
local utils = require("scribe.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

-- Build favorites + recent list and add "Search All" button. Used by both list_spaces and select_space_with_favorites.
local function build_favorites_results()
	local data = utils.get_favorites()
	local results = {}
	if type(data) ~= "table" then
		data = { favorites = {}, recent = {} }
	end
	if data and data.favorites then
		for _, space in ipairs(data.favorites) do
			space.is_fav = true
			table.insert(results, space)
		end
		for _, space in ipairs(data.recent or {}) do
			local exists = false
			for _, res in ipairs(results) do
				if res.key == space.key then
					exists = true
					break
				end
			end
			if not exists then
				table.insert(results, space)
			end
		end
	end
	if data and data.recent then
		for _, space in ipairs(data.recent) do
			local exists = false
			for _, res in ipairs(results) do
				if res.key == space.key then
					exists = true
					break
				end
			end
			if not exists then
				table.insert(results, space)
			end
		end
	end
	table.insert(results, {
		name = "🔍 Search All Confluence Spaces...",
		action = "search_all",
	})
	return results
end

-- Show favorites + "Search All" picker; when a space is chosen, call callback(space).
-- Use this from Pull, Push, Pages, or any flow that needs "pick a space (favorites first)".
function M.select_space_with_favorites(callback)
	local results = build_favorites_results()
	pickers
		.new({}, {
			prompt_title = "Select Space (Favorites)",
			finder = finders.new_table({
				results = results,
				entry_maker = function(entry)
					if entry.key then
						return {
							value = entry,
							display = "⭐ " .. entry.name .. " (" .. entry.key .. ")",
							ordinal = entry.name .. " " .. entry.key,
						}
					else
						return {
							value = entry,
							display = entry.name,
							ordinal = "zzzz",
						}
					end
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
					if selection.value.action == "search_all" then
						M.search_all_spaces(0, callback)
					elseif selection.value.key then
						callback(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

function M.list_spaces()
	M.select_space_with_favorites(function(space)
		require("scribe.pages").show_pages_for_space(space.key)
	end)
end

-- offset: optional, for pagination. on_select: optional; when user picks a space, call on_select(space). If nil, default is show_pages_for_space.
function M.search_all_spaces(offset, on_select)
	offset = offset or 0
	local limit = 50

	vim.notify(string.format("Fetching spaces %d-%d...", offset, offset + limit), vim.log.levels.INFO)

	utils.execute_cli(
		{ "spaces", "list", "--limit", tostring(limit), "--offset", tostring(offset) },
		function(result, err)
			if err then
				vim.notify("Failed to list spaces: " .. err, vim.log.levels.ERROR)
				return
			end

			local entries = result.results or result
			if type(entries) ~= "table" then
				entries = {}
			end

			if #entries >= limit then
				table.insert(entries, {
					name = "➡️  Next Page...",
					action = "next_page",
					type = "system",
					ordinal = "zzzz",
				})
			end

			pickers
				.new({}, {
					prompt_title = string.format("All Spaces (Offset: %d)", offset),
					finder = finders.new_table({
						results = entries,
						entry_maker = function(entry)
							if entry.action == "next_page" then
								return {
									value = entry,
									display = entry.name,
									ordinal = "zzzz",
								}
							end
							return {
								value = entry,
								display = string.format("%s (%s) - %s", entry.name, entry.key, entry.type or "Space"),
								ordinal = entry.name .. " " .. entry.key,
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
								M.search_all_spaces(offset + limit, on_select)
							elseif selection.value.key then
								utils.save_favorites(selection.value)
								if on_select then
									on_select(selection.value)
								else
									require("scribe.pages").show_pages_for_space(selection.value.key)
								end
							end
						end)

						map("i", "<A-a>", function()
							local selection = action_state.get_selected_entry()
							if selection and selection.value and selection.value.key then
								utils.save_favorites(selection.value)
							end
						end)

						return true
					end,
				})
				:find()
		end
	)
end

return M
