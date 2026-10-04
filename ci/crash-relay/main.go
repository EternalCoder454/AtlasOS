// atlas-crash-relay: takes Sentry-style crash reports from Atlas Updater and
// files them as GitHub issues, so the clients need no GitHub token.
package main

import (
	"context"
	"errors"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

type config struct {
	repo, tokenFile, stateDir, listen, key, api string
	proxySecret                                 string // empty: no proxy check
	proxySecretSet                              bool   // the variable was set, even if blank
}

func env(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

func loadConfig() config {
	secret, secretSet := os.LookupEnv("RELAY_PROXY_SECRET")
	return config{
		repo:           env("GITHUB_REPO", "EternalCoder454/AtlasOS"),
		tokenFile:      os.Getenv("TOKEN_FILE"),
		stateDir:       env("STATE_DIR", "/state"),
		listen:         env("LISTEN", ":8080"),
		key:            os.Getenv("SENTRY_KEY"),
		proxySecret:    strings.TrimSpace(secret),
		proxySecretSet: secretSet,
		api:            env("GITHUB_API", "https://api.github.com"),
	}
}

func (c config) validate() error {
	if c.key == "" {
		return errors.New("SENTRY_KEY is not set: refusing to start without a client key")
	}
	if c.proxySecretSet && len(c.proxySecret) < 32 {
		return errors.New("RELAY_PROXY_SECRET is set but blank or shorter than 32 characters: refusing to start with the proxy check weakened")
	}
	return nil
}

// healthcheck is for the container's HEALTHCHECK: the image has no curl.
func healthcheck(listen string) int {
	host, port, err := net.SplitHostPort(listen)
	if err != nil {
		return 1
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	c := http.Client{Timeout: 3 * time.Second}
	resp, err := c.Get("http://" + net.JoinHostPort(host, port) + "/healthz")
	if err != nil {
		return 1
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func main() {
	cfg := loadConfig()
	if len(os.Args) > 1 && os.Args[1] == "-healthcheck" {
		os.Exit(healthcheck(cfg.listen))
	}
	if err := cfg.validate(); err != nil {
		log.Fatal(err)
	}
	if cfg.proxySecret == "" {
		log.Print("warning: RELAY_PROXY_SECRET is not set, X-Forwarded-For is trusted from any peer")
	}
	if cfg.tokenFile == "" {
		log.Fatal("TOKEN_FILE is not set")
	}
	raw, err := os.ReadFile(cfg.tokenFile)
	if err != nil {
		log.Fatalf("reading token: %v", err)
	}
	token := strings.TrimSpace(string(raw))
	if token == "" {
		log.Fatal("token file is empty")
	}
	if err := os.MkdirAll(cfg.stateDir, 0o700); err != nil {
		log.Fatal(err)
	}
	st, err := loadState(filepath.Join(cfg.stateDir, "state.json"))
	if err != nil {
		log.Fatalf("loading state: %v", err)
	}
	s := newServer(cfg, newGitHub(cfg.api, cfg.repo, token), st)
	srv := &http.Server{
		Addr:              cfg.listen,
		Handler:           s.handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      90 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
	go func() {
		for range time.Tick(5 * time.Minute) {
			s.sweep()
		}
	}()
	ln, err := net.Listen("tcp", cfg.listen)
	if err != nil {
		log.Fatal(err)
	}
	stop := make(chan struct{})
	go func() {
		c := make(chan os.Signal, 1)
		signal.Notify(c, syscall.SIGTERM, syscall.SIGINT)
		<-c
		close(stop)
	}()
	log.Printf("listening on %s, filing to %s", cfg.listen, cfg.repo)
	if err := runServer(srv, ln, s, stop, drainTime); err != nil {
		log.Fatal(err)
	}
}

// drainTime is how long in-flight reports get after SIGTERM; compose.yaml's
// stop_grace_period must be longer.
const drainTime = 42 * time.Second

// runServer serves on ln until stop is closed, then waits for in-flight
// requests (up to drain) and saves the state before returning.
func runServer(srv *http.Server, ln net.Listener, s *server, stop <-chan struct{}, drain time.Duration) error {
	done := make(chan struct{})
	go func() {
		defer close(done)
		<-stop
		ctx, cancel := context.WithTimeout(context.Background(), drain)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			log.Printf("shutdown: %v", err)
			_ = srv.Close()
		}
	}()
	err := srv.Serve(ln)
	if errors.Is(err, http.ErrServerClosed) {
		err = nil
		<-done // Serve returns at once; the drain is in Shutdown
	}
	s.mu.Lock()
	// Only when a save failed earlier: re-saving unchanged state would rotate
	// state.json.bak to equal state.json.
	if s.st.dirty {
		if serr := s.st.save(); serr != nil {
			log.Printf("saving state at exit: %v", serr)
		}
	}
	s.mu.Unlock()
	return err
}
