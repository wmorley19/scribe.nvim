package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

type ChalkClient struct {
	BaseURL  string
	Username string
	APIToken string
	Client   *http.Client
}

type CreateChalkPageRequest struct {
	Type  string `json:"type"`
	Title string `json:"title"`
	Space struct {
		Key string `json:"key"`
	} `json:"space"`
	Body struct {
		Storage struct {
			Value          string `json:"value"`
			Representation string `json:"representation"`
		} `json:"storage"`
	} `json:"body"`
	Ancestors []struct {
		ID string `json:"id"`
	} `json:"ancestors,omitempty"`
}

type UpdateChalkPageRequest struct {
	Version struct {
		Number int `json:"number"`
	} `json:"version"`
	Title string `json:"title"`
	Type  string `json:"type"`
	Body  struct {
		Storage struct {
			Value          string `json:"value"`
			Representation string `json:"representation"`
		} `json:"storage"`
	} `json:"body"`
}

func NewChalkClient(baseURL, username, apiToken string) *ChalkClient {
	return &ChalkClient{
		BaseURL:  strings.TrimRight(baseURL, "/"),
		APIToken: apiToken,
		Client:   &http.Client{},
	}
}

func (c *ChalkClient) doRequest(method, path string, body interface{}) ([]byte, error) {
	// Prepare request body
	var bodyData []byte
	var err error
	if body != nil {
		bodyData, err = json.Marshal(body)
		if err != nil {
			return nil, err
		}
	}

	// Try the requested path first
	fullURL := c.BaseURL + path
	var reqBody io.Reader
	if bodyData != nil {
		reqBody = bytes.NewBuffer(bodyData)
	}

	// Validate URL scheme - enforce HTTPS
	if !strings.HasPrefix(c.BaseURL, "https://") {
		return nil, fmt.Errorf("only HTTPS URLs are allowed for security from Chalk [%s]", c.BaseURL)
	}

	req, err := http.NewRequest(method, fullURL, reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+c.APIToken)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := c.Client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w (URL: %s)", err, fullURL)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// If 404 and path doesn't contain /wiki/, try with /wiki/ prefix (Chalk Cloud)
	if resp.StatusCode == 404 && !strings.Contains(path, "/wiki/") {
		wikiPath := strings.Replace(path, "/rest/api/", "/wiki/rest/api/", 1)
		if wikiPath != path {
			wikiURL := c.BaseURL + wikiPath
			wikiReqBody := bytes.NewBuffer(bodyData)
			wikiReq, err := http.NewRequest(method, wikiURL, wikiReqBody)
			if err == nil {
				wikiReq.Header.Set("Authorization", "Bearer "+c.APIToken)
				wikiReq.Header.Set("Content-Type", "application/json")
				wikiReq.Header.Set("Accept", "application/json")
				wikiResp, err := c.Client.Do(wikiReq)
				if err == nil {
					defer wikiResp.Body.Close()
					wikiRespBody, err := io.ReadAll(wikiResp.Body)
					if err == nil {
						if wikiResp.StatusCode < 400 {
							return wikiRespBody, nil
						}
						// Wiki path also failed, return original error
					}
				}
			}
		}
	}

	if resp.StatusCode >= 400 {
		// Sanitize error message to avoid leaking sensitive info
		errorMsg := string(respBody)
		// Limit error message length to prevent huge responses
		if len(errorMsg) > 500 {
			errorMsg = errorMsg[:500] + "..."
		}
		// Don't include full URL in error (might contain credentials in some cases)
		return nil, fmt.Errorf("API error (status %d): %s", resp.StatusCode, errorMsg)
	}

	return respBody, nil
}

func (c *ChalkClient) ListSpaces(opts *ListOptions) ([]Space, error) {
	limit := 10
	offset := 0

	if opts != nil {
		if opts.Limit > 0 {
			limit = opts.Limit
		}
		if opts.Offset > 0 {
			offset = opts.Offset
		}
	}
	endpoint := fmt.Sprintf("/rest/api/space?limit=%d&start=%d", limit, offset)
	respBody, err := c.doRequest("GET", endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("ChalkClient (%s) error: %v", c.BaseURL, err)
	}

	var spacesResp SpacesResponse
	if err := json.Unmarshal(respBody, &spacesResp); err != nil {
		return nil, err
	}

	return spacesResp.Results, nil
}

// Fetch all spaces by looping through the pagination
func (c *ChalkClient) ListAllSpaces() ([]Space, error) {
	var allSpaces []Space
	limit := 500 // Maximize batch size for speed
	start := 0

	for {
		endpoint := fmt.Sprintf("/rest/api/space?limit=%d&start=%d", limit, start)
		respBody, err := c.doRequest("GET", endpoint, nil)
		if err != nil {
			return nil, err
		}

		var spacesResp SpacesResponse
		if err := json.Unmarshal(respBody, &spacesResp); err != nil {
			return nil, err
		}

		allSpaces = append(allSpaces, spacesResp.Results...)

		// If we got fewer than the limit, we're on the last page
		if len(spacesResp.Results) < limit {
			break
		}
		start += limit
	}
	return allSpaces, nil
}

func (c *ChalkClient) CreatePage(spaceKey, title, content, parentID string) (*Page, error) {
	req := CreatePageRequest{
		Type:  "page",
		Title: title,
	}
	req.Space.Key = spaceKey
	req.Body.Storage.Value = content
	req.Body.Storage.Representation = "storage"

	if parentID != "" {
		req.Ancestors = []struct {
			ID string `json:"id"`
		}{{ID: parentID}}
	}

	respBody, err := c.doRequest("POST", "/rest/api/content", req)
	if err != nil {
		return nil, err
	}

	var page Page
	if err := json.Unmarshal(respBody, &page); err != nil {
		return nil, err
	}

	return &page, nil
}

func (c *ChalkClient) GetPage(pageID string) (*Page, error) {
	// Validate and sanitize pageID to prevent injection
	if pageID == "" {
		return nil, fmt.Errorf("page ID cannot be empty")
	}
	// URL encode to prevent injection
	encodedPageID := url.PathEscape(pageID)
	respBody, err := c.doRequest("GET", "/rest/api/content/"+encodedPageID+"?expand=body.storage,version,space", nil)
	if err != nil {
		return nil, err
	}

	var page Page
	if err := json.Unmarshal(respBody, &page); err != nil {
		return nil, err
	}

	return &page, nil
}

func (c *ChalkClient) UpdatePage(pageID, content string) (*Page, error) {
	// Validate pageID
	if pageID == "" {
		return nil, fmt.Errorf("page ID cannot be empty")
	}
	// URL encode to prevent injection
	encodedPageID := url.PathEscape(pageID)

	page, err := c.GetPage(pageID)
	if err != nil {
		return nil, err
	}

	req := UpdatePageRequest{
		Type:  "page",
		Title: page.Title,
	}
	req.Version.Number = page.Version.Number + 1
	req.Body.Storage.Value = content
	req.Body.Storage.Representation = "storage"

	respBody, err := c.doRequest("PUT", "/rest/api/content/"+encodedPageID, req)
	if err != nil {
		return nil, err
	}

	var updatedPage Page
	if err := json.Unmarshal(respBody, &updatedPage); err != nil {
		return nil, err
	}

	return &updatedPage, nil
}

func (c *ChalkClient) SearchPages(spaceKey string, opts *ListOptions) ([]Page, error) {
	// Validate and URL encode spaceKey to prevent injection
	if spaceKey == "" {
		return nil, fmt.Errorf("space key cannot be empty")
	}
	cqlQuery := fmt.Sprintf("space = %q AND type = \"page\" order by title", spaceKey)

	//encodedSpaceKey := url.QueryEscape(spaceKey)
	params := url.Values{}
	params.Add("cql", cqlQuery)

	limit := 100
	offset := 0
	if opts != nil {
		if opts.Limit > 0 {
			limit = opts.Limit
		}
		if opts.Offset > 0 {
			offset = opts.Offset
		}
	}
	params.Add("limit", fmt.Sprintf("%d", limit))
	params.Add("offset", fmt.Sprintf("%d", offset))
	endpoint := "/rest/api/content/search?" + params.Encode()
	respBody, err := c.doRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	var pagesResp PagesResponse
	if err := json.Unmarshal(respBody, &pagesResp); err != nil {
		return nil, err
	}

	return pagesResp.Results, nil
}

// Fetch all pages in a space using CQL
func (c *ChalkClient) SearchAllPages(spaceKey string) ([]Page, error) {
	var allPages []Page
	limit := 500
	start := 0

	for {
		cql := url.QueryEscape(fmt.Sprintf("space = '%s' AND type = 'page'", spaceKey))
		endpoint := fmt.Sprintf("/rest/api/content/search?cql=%s&limit=%d&start=%d", cql, limit, start)

		respBody, err := c.doRequest("GET", endpoint, nil)
		if err != nil {
			return nil, err
		}

		var pagesResp PagesResponse
		if err := json.Unmarshal(respBody, &pagesResp); err != nil {
			return nil, err
		}

		allPages = append(allPages, pagesResp.Results...)

		if len(pagesResp.Results) < limit {
			break
		}
		start += limit
	}
	return allPages, nil
}
