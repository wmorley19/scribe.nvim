# scribe.nvim
## Push and pull your documentation pages directly from Neovim
> Current support for Confluence Cloud and Confluence Data 9.2

![Neovim Version](https://img.shields.io/badge/Neovim-0.8%2B-green.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## ✨ Features

- 📤 **Push** new markdown files to Confluence with fuzzy finder to pick space/parent page
- 📥 **Pull** existing pages from Confluence and convert them to markdown for easy edits and updates
- 🔄 **Update** existing pages with local changes
- 🔍 **Browse** spaces and pages using Telescope
- 📝 **Automatic conversion** between Markdown and Confluence Storage Format
- 🏷️ **Frontmatter tracking** for syncing page metadata

## 📦 Installation

### Requirements

- Neovim 0.8+
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Confluence Cloud or Server instance
- API token (see [Setup](#-setup))

### Using [lazy.nvim](https://github.com/folke/lazy.nvim) (Recommended)

```lua
{
  "wmorley19/scribe.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
    build = "cd cmd/scribe && go build -o ../../bin/scribe-cli .",
  config = function()
    require("scribe").setup({})
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "wmorley19/scribe.nvim",
  requires = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
        build = "cd cmd/scribe && go build -o ../../bin/scribe-cli .",
  config = function()
    require("scribe").setup({})
  end,
}
```

## 🔧 Setup

### 1. Get Your Confluence API Token

1. Visit https://your-domain/manage-profile/security/api-tokens
2. Click **Create API token**
3. Give it a label (e.g., "Neovim Plugin")
4. Copy and save the token securely

### 2. Configure Environment Variables (Recommended)

Add to your `~/.bashrc`, `~/.zshrc`, or shell config and restart shell `source ~/.zshrc`, `source ~/.bashrc` :

```bash
export SCRIBE_URL="https://your-domain.atlassian.net"
export SCRIBE_USERNAME="your-email@example.com" # Not required by Confluence Data 9.2
export SCRIBE_API_TOKEN="your-api-token-here"
export SCRIBE_PROVIDER="confluence" #or chalk, other providers coming soon 
```

### 3. Verify Installation

```vim
:checkhealth scribe
```

## 🚀 Usage

### Commands

| Command | Description |
|---------|-------------|
| `:ScribePush` | Create a new page from current buffer |
| `:ScribeUpdate` | Update existing page with local changes |
| `:ScribePull` | Download a page as markdown |
| `:ScribeSpaces` | Browse all Confluence spaces | Use C-n to check next page | 
| `:ScribePages` | Browse pages in a space | Use CQL to query for pages by title |
| `:ScribeNewDoc` | Create new document from default template | This ships as default and can be customized for your projects |
| `:ScribeNewDocTemplate` | Create new document and select from different templates for other types of docs |

When using Spaces and Pages each selection will store the file information as a favorite or recent for quick lookups
Example location: `~/.local/share/nvim/lazy/`

### Workflow: Creating a New Page

1. **Write your markdown:**
   ```markdown
   # My Documentation
   
   This is my **awesome** documentation.
   
   ## Code Example
   
   ```python
   def hello_confluence():
       print("Hello from Neovim!")
   ```
   
   ## Features
   
   - Feature 1
   - Feature 2
   - Feature 3
   ```

2. **Run `:ScribePush`**

3. **Select space** via Telescope fuzzy finder

4. **Optionally select parent page** (or skip)

5. **Enter page title**

6. **Done!** The plugin will:
   - Convert markdown to Confluence format
   - Create the page
   - Add frontmatter to track the page
   - Open the page in your browser

### Workflow: Updating a Page

After pushing, your file will have frontmatter:

```markdown
---
confluence_page_id: 123456789
confluence_space: DEV
confluence_title: My Documentation
---

# My Documentation

Updated content here...
```

Just edit and run `:ScribeUpdate` to sync changes!

### Workflow: Creating a New Document from Template

1. **Run `:ScribeNewDoc`** (or `:ScribeNewDocTemplate` to select a template)

2. **Enter document title**

3. **A new buffer opens** with the template content

4. **Fill in the template** with your content

5. **Save and push** using `:ScribePush`

The plugin includes a default template at `templates/default.md` that you can customize for your team. You can also create additional templates in the `templates/` directory.

### Workflow: Pulling a Page

1. Run `:ScribePull`
2. Select space
3. Select page
4. Page opens in new buffer with frontmatter

## 📝 Markdown Support

### Supported Elements

| Markdown | Confluence | Status |
|----------|------------|--------|
| `# Headers` | `<h1>-<h6>` | ✅ Full support |
| `**bold**` | `<strong>` | ✅ Full support |
| `*italic*` | `<em>` | ✅ Full support |
| `` `code` `` | `<code>` | ✅ Full support |
| Code blocks | Code macro | ✅ With syntax highlighting |
| `[links](url)` | `<a href>` | ✅ Full support |
| `- lists` | `<ul><li>` | ✅ Full support |
| `1. lists` | `<ol><li>` | ✅ Full support |
| `> quotes` | `<blockquote>` | ✅ Full support |
| `---` | `<hr>` | ✅ Full support |
| Tables | Tables | ⚠️ Basic support |
| Images | Attachments | 🔜 Planned |

### Example Conversion

**Markdown:**
```markdown
## Code Example

Here's some Python code:

```python
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)
```

## 🔒 Security

**IMPORTANT**: This plugin handles sensitive credentials (API tokens). Follow these security best practices:

- ✅ **Never commit credentials** to version control
- ✅ **Use environment variables** instead of hardcoding in config
- ✅ **Rotate API tokens** regularly
- ✅ **Use HTTPS only** (enforced by the plugin)
- ✅ **Review file permissions** on config files containing credentials

The plugin enforces HTTPS connections and validates inputs to prevent common attacks. 
## 🔍 Troubleshooting

### Binary not found

Run the health check:
```vim
:checkhealth scribe
```

### Authentication errors

- Verify your API token is correct
- Check your username (should be your email)
- Ensure SCRIBE_URL is correct (include https://)

### Markdown conversion issues

The plugin supports most common Markdown features. If something doesn't convert correctly:
1. Check if it's in the supported features list
2. Open an issue with examples

### Permission denied

```bash
chmod +x ~/.local/share/nvim/lazy/scribe.nvim/bin/scribe-cli-*
```

## 🤝 Contributing

Contributions welcome! Areas for improvement:

- 📸 Image upload support
- 📊 Better table conversion
- 🔄 Conflict resolution
- 📎 Attachment handling
- 🔍 Advanced search
- 📝 Templates

## 📄 License

MIT License - see LICENSE file

## 🙏 Acknowledgments

Built with:
- [Neovim](https://neovim.io/)
- [Telescope](https://github.com/nvim-telescope/telescope.nvim)
- [Go](https://golang.org/)
- [Cobra](https://github.com/spf13/cobra)

## 📞 Support

- 🐛 [Report bugs](https://github.com/wmorley19/scribe.nvim/issues)
- 💡 [Request features](https://github.com/wmorley19/scribe.nvim/issues)
- ⭐ Star the repo if you find it useful!

---
