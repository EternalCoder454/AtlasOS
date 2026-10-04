package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	maxBody      = 256 << 10
	openCacheTTL = 5 * time.Minute
)

type limits struct {
	ipPerHour, newPerIPDay, newPerDay, commentsPerDay, commentsPerIssueDay int
	ipMapMax, overflowPerHour, newPer48Day                                 int
}

type ipEntry struct {
	hits []time.Time
	day  string
	newN int
}

type sigLock struct {
	ch   chan struct{}
	refs int
}

type server struct {
	cfg config
	gh  *github
	st  *state
	lim limits
	now func() time.Time

	lockWait   time.Duration // longest wait for another report of the same signature
	reqTimeout time.Duration // budget for one report's GitHub work

	mu sync.Mutex // the state, briefly; never held across a GitHub call

	sigMu    sync.Mutex // serialises work on one signature, across GitHub calls
	sigLocks map[string]*sigLock

	ipMu     sync.Mutex // memory only: IP keys are never written or logged
	ips      map[string]*ipEntry
	overflow []time.Time
}

func newServer(cfg config, gh *github, st *state) *server {
	return &server{cfg: cfg, gh: gh, st: st, now: time.Now,
		lockWait: 20 * time.Second, reqTimeout: 40 * time.Second,
		sigLocks: map[string]*sigLock{}, ips: map[string]*ipEntry{},
		lim: limits{ipPerHour: 10, newPerIPDay: 3, newPerDay: 30, commentsPerDay: 200,
			commentsPerIssueDay: 10, ipMapMax: 50000, overflowPerHour: 100, newPer48Day: 6}}
}

func (s *server) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		_, _ = io.WriteString(w, "ok\n")
	})
	mux.HandleFunc("/api/1/store/", s.store)
	return mux
}

func reply(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func fail(w http.ResponseWriter, code int, msg string) {
	reply(w, code, map[string]string{"error": msg})
}

func (s *server) keyOK(r *http.Request) bool {
	h, ok := strings.CutPrefix(r.Header.Get("X-Sentry-Auth"), "Sentry ")
	if !ok {
		return false
	}
	for _, p := range strings.Split(h, ",") {
		if k, v, ok := strings.Cut(strings.TrimSpace(p), "="); ok && k == "sentry_key" {
			return subtle.ConstantTimeCompare([]byte(v), []byte(s.cfg.key)) == 1
		}
	}
	return false
}

// proxyOK checks the shared secret Caddy adds, when one is configured.
func (s *server) proxyOK(r *http.Request) bool {
	if s.cfg.proxySecret == "" {
		return true
	}
	return subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Relay-Proxy")), []byte(s.cfg.proxySecret)) == 1
}

func peerIP(r *http.Request) string {
	if h, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return h
	}
	return r.RemoteAddr
}

// clientIP is the rightmost X-Forwarded-For entry (the one Caddy adds), else
// the peer address. Entries further left are client-controlled, so this is
// only right when every request comes through Caddy; set RELAY_PROXY_SECRET
// so proxyOK enforces that.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		if ip := strings.TrimSpace(parts[len(parts)-1]); ip != "" {
			return ip
		}
	}
	return peerIP(r)
}

// ipKey is the key limits are counted under: the address, or the /64 for IPv6.
func ipKey(raw string) string {
	a, err := netip.ParseAddr(raw)
	if err != nil {
		return capRunes(raw, 64)
	}
	a = a.Unmap()
	if a.Is6() {
		p, _ := a.WithZone("").Prefix(64)
		return p.String()
	}
	return a.String()
}

func pruneHits(v []time.Time, cut time.Time) []time.Time {
	for len(v) > 0 && v[0].Before(cut) {
		v = v[1:]
	}
	return v
}

// allowIP records a request from key and reports whether it is within the
// hourly limit. When the table is full, unknown keys share one global limit.
func (s *server) allowIP(key string) (bool, int) {
	s.ipMu.Lock()
	defer s.ipMu.Unlock()
	now := s.now()
	cut := now.Add(-time.Hour)
	e := s.ips[key]
	if e == nil {
		if len(s.ips) >= s.lim.ipMapMax {
			s.overflow = pruneHits(s.overflow, cut)
			if len(s.overflow) >= s.lim.overflowPerHour {
				return false, max(1, int(s.overflow[0].Add(time.Hour).Sub(now).Seconds())+1)
			}
			s.overflow = append(s.overflow, now)
			return true, 0
		}
		e = &ipEntry{}
		s.ips[key] = e
	}
	e.hits = pruneHits(e.hits, cut)
	if len(e.hits) >= s.lim.ipPerHour {
		return false, max(1, int(e.hits[0].Add(time.Hour).Sub(now).Seconds())+1)
	}
	e.hits = append(e.hits, now)
	return true, 0
}

// sweep drops IPs with nothing left to remember. It runs on a timer.
func (s *server) sweep() {
	s.ipMu.Lock()
	defer s.ipMu.Unlock()
	now := s.now()
	cut, today := now.Add(-time.Hour), now.UTC().Format("2006-01-02")
	for k, e := range s.ips {
		e.hits = pruneHits(e.hits, cut)
		if len(e.hits) == 0 && e.day != today {
			delete(s.ips, k)
		}
	}
	s.overflow = pruneHits(s.overflow, cut)
}

func (s *server) ipNewDelta(key string, d, limit int) bool {
	s.ipMu.Lock()
	defer s.ipMu.Unlock()
	e := s.ips[key]
	if e == nil {
		if d <= 0 || len(s.ips) >= s.lim.ipMapMax {
			return true // over the table cap: the global limits apply
		}
		e = &ipEntry{}
		s.ips[key] = e
	}
	if today := s.now().UTC().Format("2006-01-02"); e.day != today {
		e.day, e.newN = today, 0
	}
	if d > 0 && e.newN >= limit {
		return false
	}
	e.newN = max(0, e.newN+d)
	return true
}

// key48 is the /48 an IPv6 /64 key belongs to, or "" for IPv4 and odd keys.
func key48(key string) string {
	p, err := netip.ParsePrefix(key)
	if err != nil || p.Bits() != 64 || !p.Addr().Is6() {
		return ""
	}
	q, _ := p.Addr().Prefix(48)
	return "48:" + q.String()
}

// ipNew counts a new issue (d=1) or refunds one (d=-1) against the source's
// /64 and, for IPv6, its /48. A refused count leaves nothing counted.
func (s *server) ipNew(key string, d int) bool {
	if !s.ipNewDelta(key, d, s.lim.newPerIPDay) {
		return false
	}
	if k := key48(key); k != "" && !s.ipNewDelta(k, d, s.lim.newPer48Day) {
		s.ipNewDelta(key, -d, s.lim.newPerIPDay)
		return false
	}
	return true
}

func (s *server) untilMidnight() int {
	n := s.now().UTC()
	next := time.Date(n.Year(), n.Month(), n.Day()+1, 0, 0, 0, 0, time.UTC)
	return max(1, int(next.Sub(n).Seconds()))
}

func validID(id string) bool {
	if len(id) != 32 {
		return false
	}
	for _, c := range id {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	return true
}

func (s *server) store(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/api/1/store/" {
		fail(w, 404, "not found")
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		fail(w, 405, "method not allowed")
		return
	}
	if !s.proxyOK(r) {
		fail(w, 403, "forbidden")
		return
	}
	if !s.keyOK(r) {
		fail(w, 401, "bad key")
		return
	}
	ip := ipKey(clientIP(r))
	if ok, retry := s.allowIP(ip); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(retry))
		fail(w, 429, "too many reports")
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBody))
	if err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			fail(w, 413, "body too large")
		} else {
			fail(w, 400, "unreadable body")
		}
		return
	}
	var ev event
	if err := json.Unmarshal(body, &ev); err != nil {
		fail(w, 400, "malformed JSON")
		return
	}
	id := strings.ToLower(ev.EventID)
	if !validID(id) {
		fail(w, 400, "bad event_id")
		return
	}
	if successTypes[ev.Tags.ReportType] {
		reply(w, 200, map[string]string{"id": id})
		return
	}
	if !reportType(ev.Tags.ReportType) {
		fail(w, 400, "unknown report_type")
		return
	}
	if !appName.MatchString(ev.Tags.App) {
		fail(w, 400, "bad app")
		return
	}
	if !ev.versionsOK() {
		fail(w, 400, "bad version")
		return
	}
	ev.sanitize()
	// Past validation the work is not tied to the client: a disconnect must
	// not cancel a GitHub create halfway (the reply would be lost).
	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), s.reqTimeout)
	defer cancel()
	res := s.process(ctx, &ev, id, ip)
	if res.retry > 0 && res.status != 200 {
		w.Header().Set("Retry-After", strconv.Itoa(res.retry))
	}
	switch {
	case res.status == 429:
		fail(w, 429, "daily limit reached")
	case res.status != 200:
		fail(w, res.status, "could not file the report")
	default:
		reply(w, 200, map[string]string{"id": id, "url": res.url})
	}
}

type result struct {
	status int
	url    string
	retry  int
	note   string // for the log line only
}

func (s *server) lockSig(ctx context.Context, sig string) (func(), error) {
	s.sigMu.Lock()
	l := s.sigLocks[sig]
	if l == nil {
		l = &sigLock{ch: make(chan struct{}, 1)}
		s.sigLocks[sig] = l
	}
	l.refs++
	s.sigMu.Unlock()
	release := func() {
		s.sigMu.Lock()
		if l.refs--; l.refs == 0 {
			delete(s.sigLocks, sig)
		}
		s.sigMu.Unlock()
	}
	// The client gives up after 30 s, so don't wait longer than lockWait.
	t := time.NewTimer(s.lockWait)
	defer t.Stop()
	select {
	case l.ch <- struct{}{}:
		return func() { <-l.ch; release() }, nil
	case <-t.C:
		release()
		return nil, errLockWait
	case <-ctx.Done():
		release()
		return nil, ctx.Err()
	}
}

var errLockWait = errors.New("timed out waiting for another report of the same signature")

// ghFail turns a GitHub error into a status for the client: 503 when the work
// was cancelled or GitHub is rate limiting (with Retry-After), else 502.
func ghFail(ctx context.Context, err error) result {
	if ctx.Err() != nil {
		return result{status: 503, retry: 30, note: "cancelled"}
	}
	if rl, wait := rateLimited(err); rl {
		return result{status: 503, retry: wait, note: "github rate limit"}
	}
	if statusOf(err) == 401 {
		return result{status: 503, retry: 300, note: "github token rejected"}
	}
	return result{status: 502, retry: 60, note: "github error"}
}

func (s *server) setOpen(si *sigInfo, v bool) {
	s.mu.Lock()
	si.Open = v
	s.mu.Unlock()
}

// transient: GitHub or the network failing, not a verdict on the issue.
func transient(err error) bool {
	st := statusOf(err)
	rl, _ := rateLimited(err)
	return rl || st == 0 || st == 401 || st == 429 || st >= 500
}

// issueState is "open", "closed" or "gone". An issue seen open is trusted for
// five minutes. An issue that can't be read for good (deleted, hidden,
// repeatedly refused) counts as gone, so a signature never gets stuck. Rate
// limits, outages and network errors are never a reason to call it gone.
func (s *server) issueState(ctx context.Context, si *sigInfo) (string, error) {
	if !si.OpenAt.IsZero() && s.now().Sub(si.OpenAt) < openCacheTTL {
		return "open", nil
	}
	iss, err := s.gh.getIssue(ctx, si.Issue)
	st := statusOf(err)
	switch {
	case err == nil:
		si.Fails = 0
		if iss.State == "open" {
			si.OpenAt = s.now()
			s.setOpen(si, true)
			return "open", nil
		}
		s.setOpen(si, false)
		return "closed", nil
	case errors.Is(err, errNotFound):
		s.setOpen(si, false)
		return "gone", nil
	case ctx.Err() != nil, transient(err):
		return "", err
	case st == 403, st == 451:
		s.setOpen(si, false)
		return "gone", nil
	default:
		if si.Fails++; si.Fails >= 5 {
			s.setOpen(si, false)
			return "gone", nil
		}
		return "", err
	}
}

func (s *server) saveLocked() error {
	if err := s.st.save(); err != nil {
		log.Printf("saving state: %v", err)
		return err
	}
	return nil
}

// process files or counts one report and logs one line for the outcome.
func (s *server) process(ctx context.Context, ev *event, id, ip string) result {
	sig := signature(ev)
	res := s.process1(ctx, ev, id, ip, sig)
	log.Printf("report sig=%.8s type=%s status=%d %s", sig, ev.Tags.ReportType, res.status, res.note)
	return res
}

func (s *server) process1(ctx context.Context, ev *event, id, ip, sig string) result {
	unlock, err := s.lockSig(ctx, sig)
	if err != nil {
		if errors.Is(err, errLockWait) {
			return result{status: 503, retry: 30, note: "waited too long for the signature lock"}
		}
		return result{status: 503, retry: 30, note: "cancelled waiting for the signature lock"}
	}
	defer unlock()

	s.mu.Lock()
	s.st.rollDay(s.now())
	if u, ok := s.st.seen(id); ok {
		s.mu.Unlock()
		return result{status: 200, url: u, note: "repeat of a filed event"}
	}
	si := s.st.Sigs[sig]
	if si != nil {
		si.Last = s.st.Day
	}
	s.mu.Unlock()

	prev, count := 0, 1
	switch {
	case si != nil && si.Pending:
		// An earlier create may have gone through without us seeing the reply.
		found, err := s.gh.findBySignature(ctx, sig)
		if err != nil {
			return ghFail(ctx, err)
		}
		if found == nil {
			log.Printf("pending sig=%.8s: no issue found, creating", sig)
			prev, count = si.Prev, si.Count
			break
		}
		log.Printf("pending sig=%.8s: adopted issue #%d", sig, found.Number)
		s.mu.Lock()
		si.Issue, si.URL, si.Pending, si.Open = found.Number, found.HTMLURL, false, found.State == "open"
		s.mu.Unlock()
		if found.State == "open" {
			return s.addComment(ctx, ev, id, si)
		}
		prev, count = found.Number, si.Count+1
	case si != nil:
		state, err := s.issueState(ctx, si)
		if err != nil {
			return ghFail(ctx, err)
		}
		switch state {
		case "open":
			return s.addComment(ctx, ev, id, si)
		case "closed":
			prev = si.Issue
		}
		count = si.Count + 1
	}
	return s.newIssue(ctx, ev, id, sig, ip, si, prev, count)
}

// warnQuota logs once per UTC day (tracked in *day) that a daily quota is used
// up, for an alert on the journal. Called with s.mu held.
func (s *server) warnQuota(day *string, format string, n int) {
	if *day != s.st.Day {
		*day = s.st.Day
		log.Printf("WARNING: "+format+", refusing new issues until 00:00 UTC", n)
	}
}

func (s *server) newIssue(ctx context.Context, ev *event, id, sig, ip string, si *sigInfo, prev, count int) result {
	s.mu.Lock()
	rel := ev.released()
	if s.st.NewToday >= s.lim.newPerDay {
		s.warnQuota(&s.st.WarnDay, "daily new-issue quota of %d reached", s.lim.newPerDay)
		s.mu.Unlock()
		return result{status: 429, retry: s.untilMidnight(), note: "daily new-issue quota"}
	}
	// Half the daily quota is kept for released versions.
	if !rel && s.st.NewUnrelToday >= s.lim.newPerDay/2 {
		s.warnQuota(&s.st.WarnUnrelDay, "daily quota for unreleased versions (%d) reached", s.lim.newPerDay/2)
		s.mu.Unlock()
		return result{status: 429, retry: s.untilMidnight(), note: "unreleased-version quota"}
	}
	if !s.ipNew(ip, 1) {
		s.mu.Unlock()
		return result{status: 429, retry: s.untilMidnight(), note: "per-source new-issue limit"}
	}
	s.st.NewToday++
	if !rel {
		s.st.NewUnrelToday++
	}
	day := s.st.Day
	refund := func() {
		s.mu.Lock()
		if s.st.Day == day { // a new day has fresh counters
			s.st.NewToday = max(0, s.st.NewToday-1)
			if !rel {
				s.st.NewUnrelToday = max(0, s.st.NewUnrelToday-1)
			}
		}
		s.mu.Unlock()
		s.ipNew(ip, -1)
	}
	if si == nil || !si.Pending {
		// Keep the old issue number: if the create fails the signature still
		// knows which issue it followed.
		n := &sigInfo{Pending: true, Prev: prev, Count: count, Last: s.st.Day}
		if si != nil {
			n.Issue, n.URL, n.Open = si.Issue, si.URL, si.Open
		}
		si = n
		s.st.Sigs[sig] = si
	}
	err := s.saveLocked() // the pending marker is on disk before the create
	s.mu.Unlock()
	if err != nil {
		refund()
		return result{status: 500, note: "state save failed before create"}
	}
	iss, err := s.gh.createIssue(ctx, title(ev), issueBody(ev, sig, prev))
	if err != nil {
		refund()
		log.Printf("create failed: %v", err)
		res := ghFail(ctx, err)
		res.note += ": create failed"
		return res
	}
	s.mu.Lock()
	si.Issue, si.URL, si.Pending, si.Open = iss.Number, iss.HTMLURL, false, true
	s.st.remember(id, iss.HTMLURL)
	err = s.saveLocked()
	s.mu.Unlock()
	if err != nil {
		// The issue exists and the id is remembered in memory: say so, and
		// answer 200 so the client doesn't send it again.
		log.Printf("issue #%d created but state save failed", iss.Number)
	}
	return result{status: 200, url: iss.HTMLURL, note: fmt.Sprintf("filed issue #%d", iss.Number)}
}

func (s *server) addComment(ctx context.Context, ev *event, id string, si *sigInfo) result {
	s.mu.Lock()
	if si.CommentDay != s.st.Day {
		si.CommentDay, si.CommentsDay = s.st.Day, 0
	}
	doComment := si.CommentsDay < s.lim.commentsPerIssueDay
	day := s.st.Day
	if doComment {
		if s.st.CommentsToday >= s.lim.commentsPerDay {
			s.mu.Unlock()
			return result{status: 429, retry: s.untilMidnight(), note: "daily comment quota"}
		}
		s.st.CommentsToday++
		si.CommentsDay++
	}
	occurrence := si.Count + 1
	s.mu.Unlock()

	note := fmt.Sprintf("counted on issue #%d", si.Issue)
	if doComment {
		if err := s.gh.comment(ctx, si.Issue, commentBody(ev, occurrence)); err != nil {
			s.mu.Lock()
			if s.st.Day == day {
				s.st.CommentsToday = max(0, s.st.CommentsToday-1)
			}
			if si.CommentDay == day {
				si.CommentsDay = max(0, si.CommentsDay-1)
			}
			s.mu.Unlock()
			// Locked or otherwise closed to comments: count it and move on.
			// A 403 that is a rate limit is not that: try again later.
			rl, _ := rateLimited(err)
			if st := statusOf(err); !(st == 403 && !rl) && st != 422 {
				return ghFail(ctx, err)
			}
			note += " (comments closed)"
		} else {
			note = fmt.Sprintf("commented on issue #%d", si.Issue)
		}
	}
	s.mu.Lock()
	si.Count++
	s.st.remember(id, si.URL)
	err := s.saveLocked()
	url := si.URL
	s.mu.Unlock()
	if err != nil {
		return result{status: 500, note: note + ", state save failed"}
	}
	return result{status: 200, url: url, note: note}
}
