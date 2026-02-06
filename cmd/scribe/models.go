package main

type ScribeProvider interface {
	ListSpaces(opts *ListOptions) ([]Space, error)
	CreatePage(spaceKey, title, content, parentID string) (*Page, error)
	GetPage(pageID string) (*Page, error)
	UpdatePage(pageID, content string) (*Page, error)
	SearchPages(spaceKey string, opts *ListOptions) ([]Page, error)
}
type ListOptions struct {
	Limit  int
	Offset int
	Query  string // optional title search (CQL: title ~ "query")
}
type Space struct {
	ID   int    `json:"id"`
	Key  string `json:"key"`
	Name string `json:"name"`
	Type string `json:"type"`
}

type SpacesResponse struct {
	Results []Space `json:"results"`
}

type Page struct {
	ID      string `json:"id"`
	Type    string `json:"type"`
	Status  string `json:"status"`
	Title   string `json:"title"`
	Space   Space  `json:"space"`
	Version struct {
		Number int `json:"number"`
	} `json:"version"`
	Body struct {
		Storage struct {
			Value          string `json:"value"`
			Representation string `json:"representation"`
		} `json:"storage"`
	} `json:"body"`
	Links struct {
		WebUI string `json:"webui"`
	} `json:"_links"`
}

type PagesResponse struct {
	Results []Page `json:"results"`
}
