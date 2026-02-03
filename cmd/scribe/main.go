package main

import (
	"encoding/json"
	"fmt"
	"github.com/spf13/cobra"
	"os"
	"strings"
)

var (
	username string
	apiToken string
	spaceKey string
	pageID   string
	title    string
	filePath string
	parentID string
	limit    int
	offset   int
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "scribe-cli",
		Short: "Docuementation CLI for Neovim integration",
	}

	// Get credentials from environment variables

	// Spaces command
	spacesCmd := &cobra.Command{
		Use:   "spaces",
		Short: "Manage Confluence spaces",
	}

	listSpacesCmd := &cobra.Command{
		Use:   "list",
		Short: "List all spaces",
		RunE:  runListSpaces,
	}
	listSpacesCmd.Flags().IntVar(&limit, "limit", 50, "Limit the number of results")
	listSpacesCmd.Flags().IntVar(&offset, "offset", 0, "Starting offset for results")

	spacesCmd.AddCommand(listSpacesCmd)

	// Pages command
	pagesCmd := &cobra.Command{
		Use:   "page",
		Short: "Manage Confluence pages",
	}

	createPageCmd := &cobra.Command{
		Use:   "create",
		Short: "Create a new page",
		RunE:  runCreatePage,
	}
	createPageCmd.Flags().StringVar(&spaceKey, "space", "", "Space key (required)")
	createPageCmd.Flags().StringVar(&title, "title", "", "Page title (required)")
	createPageCmd.Flags().StringVar(&filePath, "file", "", "Markdown file path (required)")
	createPageCmd.Flags().StringVar(&parentID, "parent", "", "Parent page ID (optional)")
	createPageCmd.MarkFlagRequired("space")
	createPageCmd.MarkFlagRequired("title")
	createPageCmd.MarkFlagRequired("file")

	updatePageCmd := &cobra.Command{
		Use:   "update",
		Short: "Update an existing page",
		RunE:  runUpdatePage,
	}
	updatePageCmd.Flags().StringVar(&pageID, "id", "", "Page ID (required)")
	updatePageCmd.Flags().StringVar(&filePath, "file", "", "Markdown file path (required)")
	updatePageCmd.MarkFlagRequired("id")
	updatePageCmd.MarkFlagRequired("file")

	getPageCmd := &cobra.Command{
		Use:   "get",
		Short: "Get page content",
		RunE:  runGetPage,
	}
	getPageCmd.Flags().StringVar(&pageID, "id", "", "Page ID (required)")
	getPageCmd.MarkFlagRequired("id")

	searchPagesCmd := &cobra.Command{
		Use:   "search",
		Short: "Search pages in a space",
		RunE:  runSearchPages,
	}
	searchPagesCmd.Flags().StringVar(&spaceKey, "space", "", "Space key (required)")
	searchPagesCmd.MarkFlagRequired("space")

	pagesCmd.AddCommand(createPageCmd, updatePageCmd, getPageCmd, searchPagesCmd)

	rootCmd.AddCommand(spacesCmd, pagesCmd)

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func runListSpaces(cmd *cobra.Command, args []string) error {
	client := NewScribeClient()
	opts := &ListOptions{
		Limit:  limit,
		Offset: offset,
	}
	spaces, err := client.ListSpaces(opts)
	if err != nil {
		return err
	}

	output, err := json.MarshalIndent(spaces, "", "  ")
	if err != nil {
		return err
	}

	fmt.Println(string(output))
	return nil
}

func runCreatePage(cmd *cobra.Command, args []string) error {
	// Validate inputs
	if spaceKey == "" || title == "" || filePath == "" {
		return fmt.Errorf("space, title, and file are required")
	}

	// Validate file path to prevent directory traversal
	if strings.Contains(filePath, "..") {
		return fmt.Errorf("invalid file path")
	}

	client := NewScribeClient()

	content, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read file: %w", err)
	}

	confluenceContent := ConvertMarkdownToConfluence(string(content))

	page, err := client.CreatePage(spaceKey, title, confluenceContent, parentID)
	if err != nil {
		return err
	}

	output, err := json.MarshalIndent(page, "", "  ")
	if err != nil {
		return err
	}

	fmt.Println(string(output))
	return nil
}

func runUpdatePage(cmd *cobra.Command, args []string) error {
	// Validate inputs
	if pageID == "" || filePath == "" {
		return fmt.Errorf("page ID and file are required")
	}

	// Validate file path to prevent directory traversal
	if strings.Contains(filePath, "..") {
		return fmt.Errorf("invalid file path")
	}

	client := NewScribeClient()

	content, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read file: %w", err)
	}

	confluenceContent := ConvertMarkdownToConfluence(string(content))

	page, err := client.UpdatePage(pageID, confluenceContent)
	if err != nil {
		return err
	}

	output, err := json.MarshalIndent(page, "", "  ")
	if err != nil {
		return err
	}

	fmt.Println(string(output))
	return nil
}

func runGetPage(cmd *cobra.Command, args []string) error {
	// Validate page ID (should be numeric)
	if pageID == "" {
		return fmt.Errorf("page ID is required")
	}

	client := NewScribeClient()

	page, err := client.GetPage(pageID)
	if err != nil {
		return err
	}

	markdown := ConvertConfluenceToMarkdown(page.Body.Storage.Value)

	fmt.Println(markdown)
	return nil
}

func runSearchPages(cmd *cobra.Command, args []string) error {
	client := NewScribeClient()
	opts := &ListOptions{
		Limit:  limit,
		Offset: offset,
	}

	pages, err := client.SearchPages(spaceKey, opts)
	if err != nil {
		return err
	}

	output, err := json.MarshalIndent(pages, "", "  ")
	if err != nil {
		return err
	}

	fmt.Println(string(output))
	return nil
}
