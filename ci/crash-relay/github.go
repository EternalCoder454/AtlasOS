package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

var errNotFound = errors.New("not found")

// httpError is a GitHub reply with a status other than 2xx, 404 or 410.
type httpError struct {
	status       int
	method, path string
	limited      bool   // GitHub's rate limit, primary or secondary
	wait         int    // seconds to wait, when limited
	snippet      string // start of the reply body, cleaned and capped
}

func (e *httpError) Error() string {
	s := fmt.Sprintf("github %s %s: HTTP %d", e.method, e.path, e.status)
	if e.snippet != "" {
		s += ": " + e.snippet
	}
	return s
}

// rateLimited reports whether err is a GitHub rate limit, and how many
// seconds to wait.
func rateLimited(err error) (bool, int) {
	var he *httpError
	if errors.As(err, &he) && he.limited {
		return true, he.wait
	}
	return false, 0
}

// classify reads the headers and body of a failed reply. A 429 is always a
// rate limit; a 403 is one when GitHub says so (remaining 0, Retry-After, or
// the message), otherwise it is a real refusal.
func classify(resp *http.Response, data []byte, method, path string, now time.Time) *httpError {
	he := &httpError{status: resp.StatusCode, method: method, path: path,
		snippet: clean(string(data), 200, false)}
	low := strings.ToLower(string(data))
	ra := resp.Header.Get("Retry-After")
	he.limited = resp.StatusCode == http.StatusTooManyRequests ||
		resp.StatusCode == http.StatusForbidden && (resp.Header.Get("X-RateLimit-Remaining") == "0" || ra != "" ||
			strings.Contains(low, "rate limit") || strings.Contains(low, "secondary"))
	if he.limited {
		he.wait = 60
		if n, err := strconv.Atoi(ra); err == nil {
			he.wait = n
		} else if n, err := strconv.ParseInt(resp.Header.Get("X-RateLimit-Reset"), 10, 64); err == nil {
			he.wait = int(time.Unix(n, 0).Sub(now).Seconds()) + 1
		}
		he.wait = min(max(he.wait, 1), 3600)
	}
	return he
}

func statusOf(err error) int {
	var he *httpError
	if errors.As(err, &he) {
		return he.status
	}
	return 0
}

type github struct {
	base, repo, token string
	c                 *http.Client
	lastTokenWarn     atomic.Int64 // unix seconds
}

// warnToken logs a rejected token, at most once an hour.
func (g *github) warnToken() {
	now := time.Now().Unix()
	if last := g.lastTokenWarn.Load(); now-last >= 3600 && g.lastTokenWarn.CompareAndSwap(last, now) {
		log.Print("GitHub token rejected (401): renew it, see the README")
	}
}

func newGitHub(base, repo, token string) *github {
	return &github{base: base, repo: repo, token: token, c: &http.Client{Timeout: 20 * time.Second}}
}

type ghIssue struct {
	Number  int    `json:"number"`
	State   string `json:"state"`
	HTMLURL string `json:"html_url"`
}

func (g *github) do(ctx context.Context, method, path string, in, out any) error {
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	var body io.Reader
	if in != nil {
		b, err := json.Marshal(in)
		if err != nil {
			return err
		}
		body = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, g.base+path, body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+g.token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "atlas-crash-relay")
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := g.c.Do(req)
	if err != nil {
		return fmt.Errorf("github %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	switch {
	case resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusGone:
		return errNotFound
	case resp.StatusCode >= 300:
		if resp.StatusCode == http.StatusUnauthorized {
			g.warnToken()
		}
		return classify(resp, data, method, path, time.Now())
	}
	if out != nil {
		return json.Unmarshal(data, out)
	}
	return nil
}

func (g *github) getIssue(ctx context.Context, n int) (ghIssue, error) {
	var i ghIssue
	err := g.do(ctx, "GET", fmt.Sprintf("/repos/%s/issues/%d", g.repo, n), nil, &i)
	return i, err
}

func (g *github) createIssue(ctx context.Context, title, body string) (ghIssue, error) {
	var i ghIssue
	err := g.do(ctx, "POST", "/repos/"+g.repo+"/issues", map[string]any{
		"title": title, "body": body, "labels": []string{"crash"},
	}, &i)
	return i, err
}

func (g *github) comment(ctx context.Context, n int, body string) error {
	return g.do(ctx, "POST", fmt.Sprintf("/repos/%s/issues/%d/comments", g.repo, n), map[string]string{"body": body}, nil)
}

// findBySignature looks for an issue carrying the signature marker, for a
// create whose reply was lost. The newest match wins. Anyone can open an issue
// or put the marker in text, so an item counts only if it has the crash label
// and its body ends with exactly the marker line, as the relay writes it.
// Pull requests are skipped.
func (g *github) findBySignature(ctx context.Context, sig string) (*ghIssue, error) {
	q := fmt.Sprintf(`repo:%s "atlas-crash-signature: %s" in:body is:issue label:crash`, g.repo, sig)
	want := "<!-- atlas-crash-signature: " + sig + " -->"
	var out struct {
		Items []struct {
			ghIssue
			Body   string `json:"body"`
			Labels []struct {
				Name string `json:"name"`
			} `json:"labels"`
			PullRequest json.RawMessage `json:"pull_request"`
		} `json:"items"`
	}
	if err := g.do(ctx, "GET", "/search/issues?"+url.Values{"q": {q}, "per_page": {"10"}}.Encode(), nil, &out); err != nil {
		return nil, err
	}
	var best *ghIssue
	for _, it := range out.Items {
		if it.PullRequest == nil && hasLabel(it.Labels, "crash") && lastLine(it.Body) == want &&
			(best == nil || it.Number > best.Number) {
			i := it.ghIssue
			best = &i
		}
	}
	return best, nil
}

func hasLabel(ls []struct {
	Name string `json:"name"`
}, name string) bool {
	for _, l := range ls {
		if l.Name == name {
			return true
		}
	}
	return false
}

// lastLine is the last non-empty line of s, trimmed.
func lastLine(s string) string {
	lines := strings.Split(strings.ReplaceAll(s, "\r\n", "\n"), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if l := strings.TrimSpace(lines[i]); l != "" {
			return l
		}
	}
	return ""
}

