local M = {}
local data_path = vim.fn.stdpath("data") .. "/scribe_favs.json"
-- Read Favs.json to help manage large document stores
function M.get_favorites()
	if vim.fn.filereadable(data_path) == 0 then
		return { favorites = {}, recent = {}, favorite_pages = {}, recent_pages = {} }
	end
	local file = io.open(data_path, "r")
	if not file then
		return { favorites = {}, recent = {}, favorite_pages = {}, recent_pages = {} }
	end
	local content = file:read("*all")
	file:close()
	if content == "" or content == nil then
		return { favorites = {}, recent = {}, favorite_pages = {}, recent_pages = {} }
	end
	local success, decoded = pcall(vim.json.decode, content)
	if success and type(decoded) == "table" then
		decoded.favorites = decoded.favorites or {}
		decoded.recent = decoded.recent or {}
		decoded.favorite_pages = decoded.favorite_pages or {}
		decoded.recent_pages = decoded.recent_pages or {}
		return decoded
	else
		return { favorites = {}, recent = {}, favorite_pages = {}, recent_pages = {} }
	end
end

-- Write back full favorites data (spaces + pages)
local function write_favorites(data)
	data = data or M.get_favorites()
	data.favorites = data.favorites or {}
	data.recent = data.recent or {}
	data.favorite_pages = data.favorite_pages or {}
	data.recent_pages = data.recent_pages or {}
	local file = io.open(data_path, "w")
	if file then
		file:write(vim.json.encode(data))
		file:close()
	end
end

--Save Favorites to local file
function M.save_favorites(space_obj)
	if not space_obj or type(space_obj) ~= "table" or not space_obj.key then
		return
	end
	local data = M.get_favorites()
	data.recent = type(data.recent) == "table" and data.recent or {}
	table.insert(data.recent, 1, space_obj)
	if #data.recent > 10 then
		table.remove(data.recent)
	end
	write_favorites(data)
end

-- Return favorite + recent pages for a space (favorites first, then recent, deduped by id). Each entry has id, title, space_key, _links or webui.
function M.get_pages_for_space(space_key)
	local data = M.get_favorites()
	if not data or type(data) ~= "table" then
		return {}
	end
	local fav = type(data.favorite_pages) == "table" and data.favorite_pages or {}
	local rec = type(data.recent_pages) == "table" and data.recent_pages or {}
	local seen = {}
	local out = {}
	for _, p in ipairs(fav) do
		if type(p) == "table" and p.space_key == space_key and p.id and not seen[p.id] then
			seen[p.id] = true
			table.insert(out, p)
		end
	end
	for _, p in ipairs(rec) do
		if type(p) == "table" and p.space_key == space_key and p.id and not seen[p.id] then
			seen[p.id] = true
			table.insert(out, p)
		end
	end
	return out
end

-- Add page to recent (when opened). Keeps last 30 per space or global.
function M.save_recent_page(page_obj, space_key)
	if not page_obj or not page_obj.id then return end
	local data = M.get_favorites()
	if not data or type(data) ~= "table" then return end
	local rec = type(data.recent_pages) == "table" and data.recent_pages or {}
	local space_val = space_key
	if not space_val and type(page_obj.space) == "table" and page_obj.space.key then
		space_val = page_obj.space.key
	end
	local _links = nil
	if type(page_obj._links) == "table" and page_obj._links.webui then
		_links = { webui = page_obj._links.webui }
	elseif type(page_obj.Links) == "table" and page_obj.Links.WebUI then
		_links = { webui = page_obj.Links.WebUI }
	end
	local entry = {
		id = tostring(page_obj.id),
		title = page_obj.title or "Untitled",
		space_key = space_val,
		_links = _links,
	}
	-- Prepend and dedupe by id
	local new_rec = { entry }
	for _, p in ipairs(rec) do
		if type(p) == "table" and p.id ~= entry.id then
			table.insert(new_rec, p)
		end
	end
	while #new_rec > 30 do table.remove(new_rec) end
	data.recent_pages = new_rec
	write_favorites(data)
end

-- Add page to favorites (starred). Dedupe by id.
function M.add_page_favorite(page_obj, space_key)
	if not page_obj or not page_obj.id then return end
	local data = M.get_favorites()
	if not data or type(data) ~= "table" then return end
	local fav = type(data.favorite_pages) == "table" and data.favorite_pages or {}
	local space_val = space_key
	if not space_val and type(page_obj.space) == "table" and page_obj.space.key then
		space_val = page_obj.space.key
	end
	local _links = nil
	if type(page_obj._links) == "table" and page_obj._links.webui then
		_links = { webui = page_obj._links.webui }
	elseif type(page_obj.Links) == "table" and page_obj.Links.WebUI then
		_links = { webui = page_obj.Links.WebUI }
	end
	local entry = {
		id = tostring(page_obj.id),
		title = page_obj.title or "Untitled",
		space_key = space_val,
		_links = _links,
	}
	for _, p in ipairs(fav) do
		if type(p) == "table" and p.id == entry.id then return end
	end
	table.insert(fav, 1, entry)
	data.favorite_pages = fav
	write_favorites(data)
end

-- Execute confluence-cli command and return parsed JSON
function M.execute_cli(args, callback)
	local config = require("scribe").config
	local cmd = config.scribe_cli_path
	local full_args = vim.list_extend({}, args)

	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)
	local stdout_chunks = {}
	local stderr_chunks = {}

	local handle
	handle = vim.loop.spawn(cmd, {
		args = full_args,
		stdio = { nil, stdout, stderr },
	}, function(code, signal)
		stdout:close()
		stderr:close()
		handle:close()

		vim.schedule(function()
			local stdout_data = table.concat(stdout_chunks, "")
			local stderr_data = table.concat(stderr_chunks, "")

			if code ~= 0 then
				vim.notify("Confluence CLI error: " .. stderr_data, vim.log.levels.ERROR)
				callback(nil, stderr_data)
				return
			end

			local success, result = pcall(vim.json.decode, stdout_data)
			if success then
				callback(result, nil)
			else
				-- Not JSON, return raw output
				callback(stdout_data, nil)
			end
		end)
	end)

	if not handle then
		vim.notify("Failed to spawn scribe-cli", vim.log.levels.ERROR)
		callback(nil, "Failed to spawn process")
		return
	end

	stdout:read_start(function(err, data)
		if err then
			vim.notify("Error reading stdout: " .. err, vim.log.levels.ERROR)
		end
		if data then
			table.insert(stdout_chunks, data)
		end
	end)

	stderr:read_start(function(err, data)
		if err then
			vim.notify("Error reading stderr: " .. err, vim.log.levels.ERROR)
		end
		if data then
			table.insert(stderr_chunks, data)
		end
	end)
end
-- Get metadata from file frontmatter
function M.get_frontmatter()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	if #lines < 3 or lines[1] ~= "---" then
		return nil
	end

	local frontmatter = {}
	local end_index = nil

	for i = 2, #lines do
		local line = lines[i]
		-- Trim the line to handle whitespace
		line = vim.trim(line)

		if line == "---" then
			end_index = i
			break
		end

		-- More flexible pattern matching
		local key, value = line:match("^([%w_]+):%s*(.+)$")
		if key and value then
			-- Trim whitespace from value
			frontmatter[key] = vim.trim(value)
		end
	end

	if end_index then
		return frontmatter, end_index
	end

	return nil
end
-- Add or update frontmatter
function M.update_frontmatter(metadata)
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local existing, end_index = M.get_frontmatter()

	local frontmatter_lines = { "---" }
	for key, value in pairs(metadata) do
		table.insert(frontmatter_lines, string.format("%s: %s", key, value))
	end
	table.insert(frontmatter_lines, "---")
	table.insert(frontmatter_lines, "")

	if existing and end_index then
		-- Replace existing frontmatter
		local content_lines = vim.list_slice(lines, end_index + 1, #lines)
		local new_lines = vim.list_extend(frontmatter_lines, content_lines)
		vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)
	else
		-- Add new frontmatter
		local new_lines = vim.list_extend(frontmatter_lines, lines)
		vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)
	end
end

-- Get current file path
function M.get_current_file()
	return vim.api.nvim_buf_get_name(0)
end

-- Check if current buffer is markdown
function M.is_markdown()
	local ft = vim.bo.filetype
	return ft == "markdown" or ft == "md"
end

-- Join Confluence URL with webui path
function M.join_scribe_url(base_url, webui_path)
	webui_path = (webui_path and tostring(webui_path)) or ""
	if webui_path == "" then
		return (base_url and tostring(base_url)) or ""
	end
	-- If webui is already a full URL, use it
	if webui_path:match("^https?://") then
		return webui_path
	end
	base_url = (base_url and tostring(base_url)) or ""
	if base_url == "" then
		return webui_path
	end
	-- Remove trailing slashes from base URL
	base_url = base_url:gsub("/+$", "")
	-- Chalk and some backends: do not add /wiki prefix when opening pages
	local config = require("scribe").config
	local no_wiki = config and config.scribe_no_wiki
	if not no_wiki and not webui_path:match("^/wiki/") and webui_path:match("^/spaces/") then
		webui_path = "/wiki" .. webui_path
	end

	-- Join paths properly
	if webui_path:match("^/") then
		return base_url .. webui_path
	else
		return base_url .. "/" .. webui_path
	end
end

return M
