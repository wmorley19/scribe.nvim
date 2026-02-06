local M = {}
local utils = require("scribe.utils")
local spaces = require("scribe.spaces")
local pages = require("scribe.pages")

function M.pull_page()
	spaces.select_space_with_favorites(function(space)
		if not space or not space.key then
			return
		end
		-- Reuse pages picker: favorites first, then Search… with query + paginated list
		pages.show_pages_picker(space.key, function(page)
			if not page or not page.id then
				return
			end
			M.do_pull(space, page)
		end)
	end)
end

function M.do_pull(space, page)
	vim.notify("Fetching page content...", vim.log.levels.INFO)

	utils.execute_cli({
		"page",
		"get",
		"--id",
		page.id,
	}, function(result, err)
		if err then
			vim.notify("Failed to fetch page: " .. err, vim.log.levels.ERROR)
			return
		end

		-- page get returns raw markdown on stdout (result may be string)
		local content = result
		if type(content) ~= "string" then
			content = type(result) == "table" and (result.content or result.body or "") or tostring(result or "")
		end

		local title = page.title or "Untitled"
		local filename = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower() .. ".md"
		if filename == ".md" then
			filename = "page-" .. page.id .. ".md"
		end

		local target_dir = vim.fn.expand("%:p:h")
		if target_dir == "" or target_dir == "." then
			target_dir = vim.fn.getcwd()
		end
		local filepath = target_dir .. "/" .. filename

		local frontmatter = {
			"---",
			string.format("confluence_page_id: %s", page.id),
			string.format("confluence_space: %s", space.key),
			string.format("confluence_title: %s", title),
			"---",
			"",
		}
		local content_lines = vim.split(content, "\n")
		local all_lines = vim.list_extend(frontmatter, content_lines)

		local write_err = vim.fn.writefile(all_lines, filepath)
		if write_err ~= 0 then
			vim.notify("Failed to write file: " .. filepath, vim.log.levels.ERROR)
			return
		end

		vim.cmd("edit " .. vim.fn.fnameescape(filepath))
		vim.notify("Page pulled to " .. filepath, vim.log.levels.INFO)
	end)
end

return M
