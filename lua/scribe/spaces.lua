local M = {}
local utils = require("scribe.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local function build_favorites_results()
	local data = utils.get_favorites() or { favorites = {}, recent = {} }
	local results = {}
	local seen = {}

	for _, space in ipairs(data.favorites or {}) do
		if space.key and not seen[space.key] then
			space.is_fav = true
			table.insert(results, space)
			seen[space.key] = true
		end
	end

	for _, space in ipairs(data.recent or {}) do
		if space.key and not seen[space.key] then
			table.insert(results, space)
			seen[space.key] = true
		end
	end

	table.insert(results, { name = "🔍 Search All...", action = "search_all" })
	return results
end

function M.select_space_with_favorites(callback)
	pickers
		.new({}, {
			prompt_title = "Select Space",
			finder = finders.new_table({
				results = build_favorites_results(),
				entry_maker = function(entry)
					if entry.action == "search_all" then
						return { value = entry, display = entry.name, ordinal = "zzzz" }
					end
					return {
						value = entry,
						display = (entry.is_fav and "⭐ " or "🕒 ") .. entry.name,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if not selection then
						return
					end

					if selection.value.action == "search_all" then
						M.search_all_spaces(callback)
					else
						callback(selection.value) -- selection.value is the space table {key, name}
					end
				end)
				return true
			end,
		})
		:find()
end

-- ScribeSpaces command: pick a space (favorites first), then show pages for that space
function M.list_spaces()
	M.select_space_with_favorites(function(space)
		if space and space.key then
			require("scribe.pages").show_pages_for_space(space.key)
		end
	end)
end

function M.search_all_spaces(on_select)
	utils.execute_cli({ "spaces", "list", "--all" }, function(result, err)
		if err then
			vim.notify("Failed to list spaces: " .. err, vim.log.levels.ERROR)
			return
		end

		local entries
		if type(result) == "string" then
			-- Streaming output from Go CLI (key|name per line)
			entries = utils.parse_streaming_lines(result, "spaces")
		else
			entries = result.results or result
		end
		if type(entries) ~= "table" then
			entries = {}
		end

		pickers
			.new({}, {
				prompt_title = "All Spaces",
				finder = finders.new_table({
					results = entries,
					entry_maker = function(entry)
						local name = entry.name or "?"
						local key = entry.key or "?"
						local typ = entry.type or "Space"
						return {
							value = entry,
							display = string.format("%s (%s) - %s", name, key, typ),
							ordinal = name .. " " .. key,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if not selection or not selection.value then
							return
						end

						utils.save_favorites(selection.value)
						if on_select then
							on_select(selection.value)
						else
							require("scribe.pages").show_pages_for_space(selection.value.key)
						end
					end)
					return true
				end,
			})
			:find()
	end)
end

return M
