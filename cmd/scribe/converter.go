package main

import (
	"regexp"
	"strings"
)

// stripFrontmatter removes YAML frontmatter from markdown content
func stripFrontmatter(content string) string {
	lines := strings.Split(content, "\n")
	if len(lines) < 3 || lines[0] != "---" {
		return content // No frontmatter
	}

	// Find the end of frontmatter
	for i := 1; i < len(lines); i++ {
		if lines[i] == "---" {
			// Return content after frontmatter
			return strings.Join(lines[i+1:], "\n")
		}
	}

	return content // No closing --- found, return as-is
}

// ConvertMarkdownToConfluence converts Markdown to Confluence Storage Format
func ConvertMarkdownToConfluence(markdown string) string {
	// Strip frontmatter before conversion
	content := stripFrontmatter(markdown)

	// Headers
	content = regexp.MustCompile(`(?m)^# (.+)$`).ReplaceAllString(content, "<h1>$1</h1>")
	content = regexp.MustCompile(`(?m)^## (.+)$`).ReplaceAllString(content, "<h2>$1</h2>")
	content = regexp.MustCompile(`(?m)^### (.+)$`).ReplaceAllString(content, "<h3>$1</h3>")
	content = regexp.MustCompile(`(?m)^#### (.+)$`).ReplaceAllString(content, "<h4>$1</h4>")
	content = regexp.MustCompile(`(?m)^##### (.+)$`).ReplaceAllString(content, "<h5>$1</h5>")
	content = regexp.MustCompile(`(?m)^###### (.+)$`).ReplaceAllString(content, "<h6>$1</h6>")

	// Bold
	content = regexp.MustCompile(`\*\*(.+?)\*\*`).ReplaceAllString(content, "<strong>$1</strong>")
	content = regexp.MustCompile(`__(.+?)__`).ReplaceAllString(content, "<strong>$1</strong>")

	// Italic
	content = regexp.MustCompile(`\*(.+?)\*`).ReplaceAllString(content, "<em>$1</em>")
	content = regexp.MustCompile(`_(.+?)_`).ReplaceAllString(content, "<em>$1</em>")

	// Code blocks
	content = regexp.MustCompile("(?s)```(\\w+)?\\n(.+?)```").ReplaceAllStringFunc(content, func(match string) string {
		parts := regexp.MustCompile("(?s)```(\\w+)?\\n(.+?)```").FindStringSubmatch(match)
		lang := parts[1]
		code := parts[2]
		if lang == "" {
			lang = "none"
		}
		return `<ac:structured-macro ac:name="code"><ac:parameter ac:name="language">` + lang + `</ac:parameter><ac:plain-text-body><![CDATA[` + code + `]]></ac:plain-text-body></ac:structured-macro>`
	})

	// Inline code
	content = regexp.MustCompile("`(.+?)`").ReplaceAllString(content, "<code>$1</code>")

	// Links
	content = regexp.MustCompile(`\[(.+?)\]\((.+?)\)`).ReplaceAllString(content, `<a href="$2">$1</a>`)

	// Unordered lists
	content = convertUnorderedLists(content)

	// Ordered lists
	content = convertOrderedLists(content)

	// Blockquotes
	content = regexp.MustCompile(`(?m)^> (.+)$`).ReplaceAllString(content, "<blockquote><p>$1</p></blockquote>")

	// Horizontal rule
	content = regexp.MustCompile(`(?m)^---$`).ReplaceAllString(content, "<hr/>")

	// Paragraphs (wrap non-tag lines)
	lines := strings.Split(content, "\n")
	var result []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		// Don't wrap if it's already an HTML tag
		if !strings.HasPrefix(trimmed, "<") {
			result = append(result, "<p>"+trimmed+"</p>")
		} else {
			result = append(result, trimmed)
		}
	}

	return strings.Join(result, "\n")
}

func convertUnorderedLists(content string) string {
	lines := strings.Split(content, "\n")
	var result []string
	inList := false

	for _, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), "- ") || strings.HasPrefix(strings.TrimSpace(line), "* ") {
			if !inList {
				result = append(result, "<ul>")
				inList = true
			}
			text := strings.TrimSpace(line[2:])
			result = append(result, "<li>"+text+"</li>")
		} else {
			if inList {
				result = append(result, "</ul>")
				inList = false
			}
			result = append(result, line)
		}
	}
	if inList {
		result = append(result, "</ul>")
	}

	return strings.Join(result, "\n")
}

func convertOrderedLists(content string) string {
	lines := strings.Split(content, "\n")
	var result []string
	inList := false

	for _, line := range lines {
		matched := regexp.MustCompile(`^\d+\. `).MatchString(strings.TrimSpace(line))
		if matched {
			if !inList {
				result = append(result, "<ol>")
				inList = true
			}
			text := regexp.MustCompile(`^\d+\. `).ReplaceAllString(strings.TrimSpace(line), "")
			result = append(result, "<li>"+text+"</li>")
		} else {
			if inList {
				result = append(result, "</ol>")
				inList = false
			}
			result = append(result, line)
		}
	}
	if inList {
		result = append(result, "</ol>")
	}

	return strings.Join(result, "\n")
}

// ConvertConfluenceToMarkdown converts Confluence Storage Format to Markdown
func ConvertConfluenceToMarkdown(confluence string) string {
	content := confluence

	// Headers
	content = regexp.MustCompile(`<h1>(.+?)</h1>`).ReplaceAllString(content, "# $1")
	content = regexp.MustCompile(`<h2>(.+?)</h2>`).ReplaceAllString(content, "## $1")
	content = regexp.MustCompile(`<h3>(.+?)</h3>`).ReplaceAllString(content, "### $1")
	content = regexp.MustCompile(`<h4>(.+?)</h4>`).ReplaceAllString(content, "#### $1")
	content = regexp.MustCompile(`<h5>(.+?)</h5>`).ReplaceAllString(content, "##### $1")
	content = regexp.MustCompile(`<h6>(.+?)</h6>`).ReplaceAllString(content, "###### $1")

	// Bold
	content = regexp.MustCompile(`<strong>(.+?)</strong>`).ReplaceAllString(content, "**$1**")

	// Italic
	content = regexp.MustCompile(`<em>(.+?)</em>`).ReplaceAllString(content, "*$1*")

	// Code blocks
	content = regexp.MustCompile(`(?s)<ac:structured-macro ac:name="code"><ac:parameter ac:name="language">(.+?)</ac:parameter><ac:plain-text-body><!\[CDATA\[(.+?)\]\]></ac:plain-text-body></ac:structured-macro>`).ReplaceAllString(content, "```$1\n$2```")

	// Inline code
	content = regexp.MustCompile(`<code>(.+?)</code>`).ReplaceAllString(content, "`$1`")

	// Links
	content = regexp.MustCompile(`<a href="(.+?)">(.+?)</a>`).ReplaceAllString(content, "[$2]($1)")

	// Lists
	content = regexp.MustCompile(`<ul>`).ReplaceAllString(content, "")
	content = regexp.MustCompile(`</ul>`).ReplaceAllString(content, "")
	content = regexp.MustCompile(`<ol>`).ReplaceAllString(content, "")
	content = regexp.MustCompile(`</ol>`).ReplaceAllString(content, "")
	content = regexp.MustCompile(`<li>(.+?)</li>`).ReplaceAllString(content, "- $1")

	// Blockquotes
	content = regexp.MustCompile(`<blockquote><p>(.+?)</p></blockquote>`).ReplaceAllString(content, "> $1")

	// Horizontal rule
	content = regexp.MustCompile(`<hr/?>`).ReplaceAllString(content, "---")

	// Paragraphs
	content = regexp.MustCompile(`<p>(.+?)</p>`).ReplaceAllString(content, "$1\n")

	// Clean up extra newlines
	content = regexp.MustCompile(`\n{3,}`).ReplaceAllString(content, "\n\n")

	return strings.TrimSpace(content)
}
