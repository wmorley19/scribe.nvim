local M = {}

-- Get the plugin directory
local function get_plugin_dir()
	local source = debug.getinfo(1, "S").source
	if source:sub(1, 1) == "@" then
		source = source:sub(2)
	end
	-- Remove /lua/scribe/init.lua to get plugin root
	return vim.fn.fnamemodify(source, ":h:h:h")
end

-- Detect OS and architecture
local function detect_platform()
	local os = vim.loop.os_uname().sysname:lower()
	local arch = vim.loop.os_uname().machine

	if os:match("darwin") then
		os = "darwin"
	elseif os:match("linux") then
		os = "linux"
	elseif os:match("windows") then
		os = "windows"
	end

	if arch == "x86_64" or arch == "amd64" then
		arch = "amd64"
	elseif arch == "aarch64" or arch == "arm64" then
		arch = "arm64"
	end

	return os, arch
end

-- Find the CLI binary
local function find_cli_binary()
	local plugin_dir = get_plugin_dir()
	local bin_dir = plugin_dir .. "/bin"
	local os, arch = detect_platform()

	-- Try platform-specific binary first
	local ext = os == "windows" and ".exe" or ""
	local platform_binary = string.format("%s/scribe-cli-%s-%s%s", bin_dir, os, arch, ext)

	if vim.fn.filereadable(platform_binary) == 1 then
		return platform_binary
	end

	-- Try generic binary
	local generic_binary = bin_dir .. "/scribe-cli" .. ext
	if vim.fn.filereadable(generic_binary) == 1 then
		return generic_binary
	end

	-- Try to find in PATH
	local path_binary = vim.fn.exepath("scribe-cli")
	if path_binary ~= "" then
		return path_binary
	end

	return nil
end

-- Configuration
M.config = {
	scribe_cli_path = nil, -- Will be auto-detected
	scribe_url = vim.env.SCRIBE_URL or "",
	scribe_username = vim.env.SCRIBE_USERNAME or "",
	scribe_api_token = vim.env.SCRIBE_API_TOKEN or "",
	template_path = nil, -- Path to custom template file (optional)
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Auto-detect CLI binary if not specified
	if not M.config.scribe_cli_path or M.config.scribe_cli_path == "" then
		M.config.scribe_cli_path = find_cli_binary()
	end

	-- Validate CLI binary exists
	if not M.config.scribe_cli_path then
		vim.notify(
			"Scribe CLI binary not found. Please run the install script:\n"
				.. "cd "
				.. get_plugin_dir()
				.. " && bash scripts/install.sh",
			vim.log.levels.ERROR
		)
		return
	end

	if vim.fn.filereadable(M.config.scribe_cli_path) == 0 then
		vim.notify("Scribe CLI binary not found at: " .. M.config.scribe_cli_path, vim.log.levels.ERROR)
		return
	end

	-- Set environment variables for the CLI
	vim.env.SCRIBE_URL = M.config.scribe_url
	vim.env.SCRIBE_USERNAME = M.config.scribe_username
	vim.env.SCRIBE_API_TOKEN = M.config.scribe_api_token

	-- Validate configuration
	if M.config.scribe_url == "" or M.config.scribe_api_token == "" then
		vim.notify(
			"Confluence credentials not configured. Please set:\n"
				.. "- scribe_url\n"
				.. "- scribe_api_token\n"
				.. "Or pass them in setup()",
			vim.log.levels.WARN
		)
	end

	-- Create user commands
	vim.api.nvim_create_user_command("ScribePush", function()
		require("scribe.push").push_current_file()
	end, { desc = "Push current markdown file to Conflunce" })

	vim.api.nvim_create_user_command("ScribePull", function()
		require("scribe.pull").pull_page()
	end, { desc = "Pull a Confluence page as markdown" })

	vim.api.nvim_create_user_command("ScribeUpdate", function()
		require("scribe.update").update_current_file()
	end, { desc = "Update existing Confluence page" })

	vim.api.nvim_create_user_command("ScribeSpaces", function()
		require("scribe.spaces").list_spaces()
	end, { desc = "Browse Confluence spaces" })

	vim.api.nvim_create_user_command("ScribePages", function()
		require("scribe.pages").list_pages()
	end, { desc = "Browse Confluence pages" })

	vim.api.nvim_create_user_command("ScribeNewDoc", function()
		require("scribe.new").create_new_doc()
	end, { desc = "Create new document from template" })

	vim.api.nvim_create_user_command("ScribeNewDocTemplate", function()
		require("scribe.new").create_new_doc_with_template()
	end, { desc = "Create new document and select template" })

	vim.notify("scribe.nvim loaded successfully!", vim.log.levels.INFO)
end

return M
