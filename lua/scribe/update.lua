local M = {}
local utils = require("scribe.utils")

function M.update_current_file()
	if not utils.is_markdown() then
		vim.notify("Current buffer is not a markdown file", vim.log.levels.ERROR)
		return
	end

	local file_path = utils.get_current_file()
	if file_path == "" then
		vim.notify("Please save the file first", vim.log.levels.ERROR)
		return
	end

	-- Get page ID from frontmatter
	local frontmatter = utils.get_frontmatter()
	if not frontmatter or not frontmatter.confluence_page_id then
		vim.notify(
			"No confluence_page_id found in frontmatter. Use :ScribePush to create a new page.",
			vim.log.levels.ERROR
		)
		return
	end

	local page_id = frontmatter.confluence_page_id

	utils.execute_cli({
		"page",
		"update",
		"--id",
		page_id,
		"--file",
		file_path,
	}, function(result, err)
		if err then
			vim.notify("Failed to update: " .. err, vim.log.levels.ERROR)
			return
		end

		vim.notify("Page updated successfully!", vim.log.levels.INFO)

		-- Open in browser
		local open_cmd = vim.fn.has("mac") == 1 and "open" or "xdg-open"
		local webui = (result._links and result._links.webui) or (result._link and result._link.webui) or ""
		local url = utils.join_scribe_url(require("scribe").config.scribe_url, webui)

		vim.notify("Updating Confluence page...", vim.log.levels.INFO)
		vim.fn.system(string.format("%s '%s'", open_cmd, url))
	end)
end

return M
