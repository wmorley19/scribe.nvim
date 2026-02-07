package main

import (
	"bytes"
	"fmt"
	htmltomarkdown "github.com/JohannesKaufmann/html-to-markdown"
	"github.com/JohannesKaufmann/html-to-markdown/plugin"
	"github.com/PuerkitoBio/goquery"
	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/extension"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/renderer/html"
	"regexp"
	"strings"
)

// ConvertMarkdownToConfluence uses Goldmark to generate strict XHTML
func ConvertMarkdownToConfluence(markdown string) string {
	content := stripFrontmatter(markdown)

	// 1. Configure Goldmark for Confluence compatibility
	md := goldmark.New(
		goldmark.WithExtensions(extension.GFM), // GitHub Flavored Markdown (tables, strikethrough)
		goldmark.WithParserOptions(
			parser.WithAutoHeadingID(),
		),
		goldmark.WithRendererOptions(
			html.WithXHTML(),  // CRITICAL: Generates <br/>, <hr/>, <img ... /> for Data Center validity
			html.WithUnsafe(), // Allow raw HTML (in case user manually added macros)
		),
	)

	var buf bytes.Buffer
	if err := md.Convert([]byte(content), &buf); err != nil {
		// Fallback to raw content if conversion fails (rare)
		return content
	}

	xhtml := buf.String()

	// Goldmark guarantees the structure is predictable.
	xhtml = regexp.MustCompile(`(?s)<pre><code class="language-(\w+)">(.+?)</code></pre>`).ReplaceAllStringFunc(xhtml, func(match string) string {
		parts := regexp.MustCompile(`(?s)<pre><code class="language-(\w+)">(.+?)</code></pre>`).FindStringSubmatch(match)
		lang := parts[1]
		code := parts[2]
		// Unescape HTML entities inside code block so they show up correctly in the macro
		code = strings.ReplaceAll(code, "&lt;", "<")
		code = strings.ReplaceAll(code, "&gt;", ">")
		code = strings.ReplaceAll(code, "&amp;", "&")

		return fmt.Sprintf(`<ac:structured-macro ac:name="code"><ac:parameter ac:name="language">%s</ac:parameter><ac:plain-text-body><![CDATA[%s]]></ac:plain-text-body></ac:structured-macro>`, lang, code)
	})

	// Handle generic code blocks (no language specified)
	xhtml = regexp.MustCompile(`(?s)<pre><code>(.+?)</code></pre>`).ReplaceAllStringFunc(xhtml, func(match string) string {
		parts := regexp.MustCompile(`(?s)<pre><code>(.+?)</code></pre>`).FindStringSubmatch(match)
		code := parts[1]
		code = strings.ReplaceAll(code, "&lt;", "<")
		code = strings.ReplaceAll(code, "&gt;", ">")
		code = strings.ReplaceAll(code, "&amp;", "&")

		return fmt.Sprintf(`<ac:structured-macro ac:name="code"><ac:plain-text-body><![CDATA[%s]]></ac:plain-text-body></ac:structured-macro>`, code)
	})

	return xhtml
}

// ConvertConfluenceToMarkdown uses html-to-markdown for robust parsing
func ConvertConfluenceToMarkdown(confluence string) string {
	converter := htmltomarkdown.NewConverter("", true, nil)

	// Use GFM plugin (tables, strikethrough)
	converter.Use(plugin.GitHubFlavored())

	// 1. CUSTOM RULE: Handle Confluence Code Macros
	// Confluence stores code in <ac:structured-macro ac:name="code">...
	converter.AddRules(htmltomarkdown.Rule{
		Filter: []string{"ac:structured-macro"},
		Replacement: func(content string, selec *goquery.Selection, opt *htmltomarkdown.Options) *string {
			// Check if it's a code block
			if selec.AttrOr("ac:name", "") == "code" {
				// Get language
				lang := selec.Find("ac\\:parameter[ac\\:name='language']").Text()

				// Get code content (inside CDATA usually, but parsed as text by goquery)
				code := selec.Find("ac\\:plain-text-body").Text()

				// Return standard Markdown code block
				block := fmt.Sprintf("\n```%s\n%s\n```\n", lang, code)
				return &block
			}
			// If it's not a code block, just return the inner content text (or strip it)
			// Returning nil lets other rules handle it, but here we likely want to just render text
			text := selec.Text()
			return &text
		},
	})

	// Confluence uses <ri:attachment ri:filename="image.png" /> inside <ac:image>
	converter.AddRules(htmltomarkdown.Rule{
		Filter: []string{"ac:image"},
		Replacement: func(content string, selec *goquery.Selection, opt *htmltomarkdown.Options) *string {
			filename := selec.Find("ri\\:attachment").AttrOr("ri:filename", "")
			if filename != "" {
				image := fmt.Sprintf("![%s](%s)", filename, filename)
				return &image
			}
			return nil
		},
	})

	markdown, err := converter.ConvertString(confluence)
	if err != nil {
		// Fallback to simple regex if library fails
		return confluence
	}

	return strings.TrimSpace(markdown)
}

func stripFrontmatter(content string) string {
	lines := strings.Split(content, "\n")
	if len(lines) < 3 || lines[0] != "---" {
		return content
	}
	for i := 1; i < len(lines); i++ {
		if lines[i] == "---" {
			return strings.Join(lines[i+1:], "\n")
		}
	}
	return content
}
