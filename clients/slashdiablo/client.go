package slashdiablo

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"time"
)

// newTransport bounds connection setup without capping transfer time. The
// default client has no dial timeout at all, so an unreachable file server
// stalls every request for as long as the OS takes to give up, and a single
// patch run makes a manifest request per available mod version. The timeouts
// are deliberately on the transport rather than on http.Client.Timeout, which
// would also cap the body read and break the 65MB d2gl.mpq on a slow line.
func newTransport() *http.Transport {
	return &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   10 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 30 * time.Second,
		MaxIdleConnsPerHost:   4,
	}
}

// Client encapsulates the details of the SlashDiablo API.
type Client struct {
	address string
	client  *http.Client
}

// GetFile will the file by the given path in the repository set on the service.
func (c *Client) GetFile(filePath string) (io.ReadCloser, error) {
	return c.get(fmt.Sprintf("%s/slashdiablo-patches/%s", c.address, filePath))
}

// GetNews will fetch the remote news source.
func (c *Client) GetNews() (io.ReadCloser, error) {
	return c.get(fmt.Sprintf("%s/news.json", c.address))
}

// GetAvailableMods will fetch the remote available mods source.
func (c *Client) GetAvailableMods() (io.ReadCloser, error) {
	return c.get(fmt.Sprintf("%s/available_mods_1.1.0.json", c.address))
}

// get performs the request and returns the body only if the server actually
// served the file. Without the status check an error page is handed back as if
// it were content, which shows up as "invalid character '<' looking for
// beginning of value" when a manifest is parsed, and silently writes the HTML
// to disk when a patch file is downloaded.
func (c *Client) get(url string) (io.ReadCloser, error) {
	resp, err := c.client.Get(url)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		resp.Body.Close()
		return nil, fmt.Errorf("unexpected status code %d for %s", resp.StatusCode, url)
	}

	return resp.Body, nil
}

// NewClient returns a new client with all dependencies setup.
func NewClient(address string) Client {
	return Client{
		address: address,
		client:  &http.Client{Transport: newTransport()},
	}
}
