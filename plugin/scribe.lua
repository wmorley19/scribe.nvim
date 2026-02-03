-- plugin/confluence.lua
-- This file auto-loads when Neovim starts

if vim.g.loaded_confluence then
	return
end
vim.g.loaded_confluence = 1

-- Don't auto-setup - let users call setup() in their config
-- This gives them control over when/how the plugin initializes
