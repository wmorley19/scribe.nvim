package main

import (
	"net/http"
	"os"
)

// ProviderType identifies which service we are talking to
type ProviderType string

const (
	Confluence ProviderType = "cloud"
	Chalk      ProviderType = "chalk"
)

func NewScribeClient() ScribeProvider {
	// 1. Check for an explicit override (e.g., SCRIBE_PROVIDER=chalk)
	provider := ProviderType(os.Getenv("SCRIBE_PROVIDER"))

	// 2. Logic to "Auto-Detect" if no override is provided
	if provider == "" {
		username := os.Getenv("SCRIBE_USERNAME")
		if username == "" {
			provider = Chalk
		} else {
			provider = Confluence
		}
	}

	// 3. Return the correct "Actor"
	switch provider {
	case Chalk:
		return &ChalkClient{
			BaseURL:  os.Getenv("SCRIBE_URL"),
			APIToken: os.Getenv("SCRIBE_API_TOKEN"),
			Client:   &http.Client{},
		}
	default:
		return &ConfluenceClient{
			BaseURL:  os.Getenv("SCRIBE_URL"),
			Username: os.Getenv("SCRIBE_USERNAME"),
			APIToken: os.Getenv("SCRIBE_API_TOKEN"),
			Client:   &http.Client{},
		}
	}
}
