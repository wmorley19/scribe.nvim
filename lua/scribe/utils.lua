local M = {}
local data_path = vim.fn.stdpath("data") .. "/scribe_favs.json"
-- Read Favs.json to help manage large document stores
function M.get_favorites()
	if vim.fn.filereadable(data_path) == 0 then
		return { favorites = {}, recent = {} }
	end
	local file = io.open(data_path, "r")
	if not file then
		return { favorites = {}, recent = {} }
	end
	local content = file:read("*all")
	file:close()
	if content == "" or content == nil then
		return { favorites = {}, recent = {} }
	end
	local success, decoded = pcall(vim.json.decode, content)
	if success and type(decoded) == "table" then
		decoded.favorites = decoded.favorites or {}
		decoded.recent = decoded.recent or {}
		return decoded
	else
		return { favorites = {}, recent = {} }
	end
end

--Save Favorites to local file
function M.save_favorites(space_obj)
	local data = M.get_favorites()

	table.insert(data.recent, 1, space_obj)
	if #data.recent > 10 then
		table.remove(data.recent)
	end
	local file = io.open(data_path, "w")
	file:write(vim.json.encode(data))
	file:close()
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

-- Parse streaming line format from Go CLI: "key|name" or "id|title" per line.
-- Returns a table of entries suitable for result.results (spaces: {key, name}; pages: {id, title}).
function M.parse_streaming_lines(stdout_data, kind)
	if type(stdout_data) ~= "string" or stdout_data == "" then
		return {}
	end
	local results = {}
	for _, line in ipairs(vim.split(stdout_data, "\n")) do
		line = vim.trim(line)
		if line == "" then
			goto continue
		end
		local a, b = line:match("^([^|]+)|(.+)$")
		if a and b then
			if kind == "spaces" then
				table.insert(results, { key = vim.trim(a), name = vim.trim(b) })
			elseif kind == "pages" then
				table.insert(results, { id = vim.trim(a), title = vim.trim(b) })
			end
		end
		::continue::
	end
	return results
end

-- Join Confluence/Scribe base URL with webui path
function M.join_scribe_url(base_url, webui_path)
	if not webui_path or webui_path == "" then
		return base_url or ""
	end

	-- If webui is already a full URL, use it
	if webui_path:match("^https?://") then
		return webui_path
	end

	-- Guard against nil base_url (e.g. config not set)
	if not base_url or base_url == "" then
		return webui_path:match("^/") and webui_path or ("/" .. webui_path)
	end

	-- Remove trailing slashes from base URL
	base_url = base_url:gsub("/+$", "")
	if not webui_path:match("^/wiki/") and webui_path:match("^/spaces/") then
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
