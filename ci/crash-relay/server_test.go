package main

import (
	"context"
	"io"
	"net"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fIssue struct {
	State    string
	Title    string
	Body     string
	Labels   []string
	Comments []string
}

type fakeGH struct {
	mu     sync.Mutex
	issues map[int]*fIssue
	calls  int
	broken bool
	badHdr bool

	loseCreate    bool // create the issue but answer 500
	commentStatus int  // answer comments with this status
	onCreate, onComment func() // test hooks
	getStatus     int  // answer issue GETs with this status
	replyBody     string // body for getStatus and commentStatus errors
	replyHdr      http.Header
}

func (f *fakeGH) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	if r.Header.Get("User-Agent") == "" || r.Header.Get("Authorization") != "Bearer tok" {
		f.badHdr = true
	}
	if f.broken {
		http.Error(w, "boom", 500)
		return
	}
	var n int
	p := r.URL.Path
	switch {
	case r.Method == "POST" && p == "/repos/o/r/issues":
		var in struct {
			Title, Body string
			Labels      []string
		}
		_ = json.NewDecoder(r.Body).Decode(&in)
		n = len(f.issues) + 1
		f.issues[n] = &fIssue{"open", in.Title, in.Body, in.Labels, nil}
		if f.onCreate != nil {
			f.onCreate()
		}
		if f.loseCreate {
			http.Error(w, "lost", 500)
			return
		}
		json.NewEncoder(w).Encode(ghIssue{n, "open", fmt.Sprintf("https://github.com/o/r/issues/%d", n)})
	case r.Method == "GET" && p == "/search/issues":
		q := r.URL.Query().Get("q")
		_, sig, _ := strings.Cut(q, "atlas-crash-signature: ")
		sig, _, _ = strings.Cut(sig, `"`)
		var items []map[string]any
		for k, i := range f.issues {
			if strings.Contains(i.Body, "atlas-crash-signature: "+sig) && strings.Contains(q, "label:crash") {
				var ls []map[string]string
				for _, l := range i.Labels {
					ls = append(ls, map[string]string{"name": l})
				}
				items = append(items, map[string]any{"number": k, "state": i.State, "body": i.Body,
					"labels": ls, "html_url": fmt.Sprintf("https://github.com/o/r/issues/%d", k)})
			}
		}
		json.NewEncoder(w).Encode(map[string]any{"items": items})
	case r.Method == "GET" && strings.HasPrefix(p, "/repos/o/r/issues/"):
		if f.getStatus != 0 {
			f.fail(w, f.getStatus)
			return
		}
		fmt.Sscanf(p, "/repos/o/r/issues/%d", &n)
		i := f.issues[n]
		if i == nil {
			http.NotFound(w, r)
			return
		}
		json.NewEncoder(w).Encode(ghIssue{n, i.State, fmt.Sprintf("https://github.com/o/r/issues/%d", n)})
	case r.Method == "POST" && strings.HasSuffix(p, "/comments"):
		if f.onComment != nil {
			f.onComment()
		}
		if f.commentStatus != 0 {
			f.fail(w, f.commentStatus)
			return
		}
		fmt.Sscanf(p, "/repos/o/r/issues/%d/comments", &n)
		var in struct{ Body string }
		_ = json.NewDecoder(r.Body).Decode(&in)
		f.issues[n].Comments = append(f.issues[n].Comments, in.Body)
		w.WriteHeader(201)
		fmt.Fprint(w, "{}")
	default:
		http.NotFound(w, r)
	}
}

type rig struct {
	t   *testing.T
	s   *server
	f   *fakeGH
	h   http.Handler
	dir string
	now time.Time
}

func newEnv(t *testing.T) *rig {
	f := &fakeGH{issues: map[int]*fIssue{}}
	ts := httptest.NewServer(f)
	t.Cleanup(ts.Close)
	dir := t.TempDir()
	st, err := loadState(filepath.Join(dir, "state.json"))
	if err != nil {
		t.Fatal(err)
	}
	e := &rig{t: t, f: f, dir: dir, now: time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC)}
	e.s = newServer(config{key: "atlasos"}, newGitHub(ts.URL, "o/r", "tok"), st)
	e.s.now = func() time.Time { return e.now }
	e.s.lim.ipPerHour = 1000
	e.s.lim.newPerIPDay = 1000
	e.h = e.s.handler()
	return e
}

func (e *rig) raw(body, auth, xff string) *httptest.ResponseRecorder {
	r := httptest.NewRequest("POST", "/api/1/store/", strings.NewReader(body))
	r.RemoteAddr = "192.0.2.1:1234"
	if auth != "" {
		r.Header.Set("X-Sentry-Auth", auth)
	}
	if xff != "" {
		r.Header.Set("X-Forwarded-For", xff)
	}
	w := httptest.NewRecorder()
	e.h.ServeHTTP(w, r)
	return w
}

const goodAuth = "Sentry sentry_version=7, sentry_key=atlasos, sentry_client=atlas-core/1"

func (e *rig) send(ev map[string]any) *httptest.ResponseRecorder {
	b, _ := json.Marshal(ev)
	return e.raw(string(b), goodAuth, "")
}

var idCounter int

func ev(msg string, funcs ...string) map[string]any {
	idCounter++
	m := map[string]any{
		"event_id": fmt.Sprintf("%032x", idCounter),
		"message":  msg,
		"tags": map[string]any{"app": "atlas-updater", "app_version": "1.2", "report_type": "panic",
			"atlasos_version": "44.20261003", "kernel": "7.2", "gpu": "RX 7900"},
		"user": map[string]any{"id": "secret-user-id"},
	}
	if len(funcs) > 0 {
		var fr []map[string]any
		for _, f := range funcs {
			fr = append(fr, map[string]any{"function": f, "instruction_addr": "0x1"})
		}
		m["exception"] = map[string]any{"values": []any{map[string]any{"stacktrace": map[string]any{"frames": fr}}}}
	}
	return m
}

func urlOf(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	if w.Code != 200 {
		t.Fatalf("status %d: %s", w.Code, w.Body)
	}
	var o map[string]string
	json.Unmarshal(w.Body.Bytes(), &o)
	return o["url"]
}

func TestAuth(t *testing.T) {
	e := newEnv(t)
	for _, a := range []string{"", "Sentry sentry_key=nope", "Basic x", "Sentry sentry_version=7"} {
		if w := e.raw(`{}`, a, ""); w.Code != 401 {
			t.Errorf("auth %q: %d", a, w.Code)
		}
	}
	if e.f.calls != 0 {
		t.Error("GitHub called")
	}
}

func TestSizeAndBadInput(t *testing.T) {
	e := newEnv(t)
	big := `{"event_id":"` + strings.Repeat("a", 300<<10) + `"}`
	if w := e.raw(big, goodAuth, ""); w.Code != 413 {
		t.Errorf("big: %d", w.Code)
	}
	if w := e.raw(`{nope`, goodAuth, ""); w.Code != 400 {
		t.Errorf("json: %d", w.Code)
	}
	for _, id := range []string{"", "short", strings.Repeat("g", 32), strings.Repeat("a", 33)} {
		if w := e.raw(fmt.Sprintf(`{"event_id":%q}`, id), goodAuth, ""); w.Code != 400 {
			t.Errorf("id %q: %d", id, w.Code)
		}
	}
}

func TestFilesIssue(t *testing.T) {
	e := newEnv(t)
	u := urlOf(t, e.send(ev("it broke at 0x1234", "main", "run", "boom")))
	if u != "https://github.com/o/r/issues/1" {
		t.Fatal(u)
	}
	i := e.f.issues[1]
	if i.Title != "Crash: atlas-updater 1.2 (panic)" || len(i.Labels) != 1 || i.Labels[0] != "crash" {
		t.Errorf("%q %v", i.Title, i.Labels)
	}
	if !strings.Contains(i.Body, "<!-- atlas-crash-signature: ") || strings.Contains(i.Body, "secret-user-id") {
		t.Error(i.Body)
	}
	if e.f.badHdr {
		t.Error("missing token or user agent")
	}
}

func TestFailureTitle(t *testing.T) {
	e := newEnv(t)
	m := ev("x")
	m["tags"].(map[string]any)["report_type"] = "update-failed"
	e.send(m)
	if got := e.f.issues[1].Title; got != "Update problem: update-failed on AtlasOS 44.20261003" {
		t.Error(got)
	}
}

func TestEscaping(t *testing.T) {
	e := newEnv(t)
	m := ev("hi @everyone\n```\n# heading\n````\n<script>alert(1)</script>", "f")
	tags := m["tags"].(map[string]any)
	tags["kernel"] = "a|b`c\nd"
	tags["category"] = "evil\n@bob #12 | `x`"
	e.send(m)
	i := e.f.issues[1]
	if strings.ContainsAny(i.Title, "\n\r") {
		t.Errorf("title %q", i.Title)
	}
	if !strings.Contains(i.Body, "`````\nhi @everyone") || !strings.Contains(i.Body, "<script>alert(1)</script>\n`````") {
		t.Errorf("fence:\n%s", i.Body)
	}
	if !strings.Contains(i.Body, "| Kernel | `abcd` |") || !strings.Contains(i.Body, "| Category | `evil@bob #12  x` |") {
		t.Errorf("table:\n%s", i.Body)
	}
	// Versions are validated before they reach a title; titleText is the
	// second line of defence.
	if got := titleText("a\n@bob #12"); got != "a @\u200bbob #\u200b12" {
		t.Errorf("titleText %q", got)
	}
	m = ev("y")
	m["tags"].(map[string]any)["app"] = strings.Repeat("a", 100)
	m["tags"].(map[string]any)["app_version"] = strings.Repeat("1", 40)
	m["tags"].(map[string]any)["report_type"] = "coredump"
	e.send(m)
	if n := len([]rune(e.f.issues[2].Title)); n > 200 {
		t.Errorf("title %d", n)
	}
}

func TestFormatRunesStripped(t *testing.T) {
	e := newEnv(t)
	m := ev("pay\u202eload\u200b\ufeff\u200d ok", "f")
	m["tags"].(map[string]any)["gpu"] = "RX\u202e 7900"
	e.send(m)
	if b := e.f.issues[1].Body; strings.ContainsAny(b, "\u202e\u200b\ufeff\u200d") || !strings.Contains(b, "payload ok") {
		t.Errorf("%q", b)
	}
}

func TestReportTypeAndApp(t *testing.T) {
	e := newEnv(t)
	set := func(k, v string) map[string]any {
		m := ev("x")
		m["tags"].(map[string]any)[k] = v
		return m
	}
	for _, m := range []map[string]any{set("report_type", "weird"), set("report_type", ""),
		set("report_type", "crash"), set("app", ""), set("app", "a b"), set("app", "a`b"),
		set("app", strings.Repeat("a", 101)), set("app", "a\nb")} {
		if w := e.send(m); w.Code != 400 {
			t.Errorf("%v: %d", m["tags"], w.Code)
		}
	}
	for _, rt := range []string{"panic", "fatal", "coredump", "update-failed", "automatic-rollback"} {
		if w := e.send(set("report_type", rt)); w.Code != 200 {
			t.Errorf("%s: %d", rt, w.Code)
		}
	}
	m := set("app", "/usr/bin/some-prog+1.x_y")
	if w := e.send(m); w.Code != 200 {
		t.Errorf("app: %d", w.Code)
	}
	// a success event is a silent 200 whatever else it holds
	m = set("report_type", "update-applied")
	m["tags"].(map[string]any)["app"] = "bad app"
	if w := e.send(m); w.Code != 200 {
		t.Errorf("success: %d", w.Code)
	}
}

func TestDedupeAndComment(t *testing.T) {
	e := newEnv(t)
	u1 := urlOf(t, e.send(ev("fail 11", "a", "b")))
	u2 := urlOf(t, e.send(ev("other 22", "a", "b")))
	if u1 != u2 || len(e.f.issues) != 1 || len(e.f.issues[1].Comments) != 1 {
		t.Fatalf("%s %s %d", u1, u2, len(e.f.issues))
	}
	if c := e.f.issues[1].Comments[0]; !strings.Contains(c, "occurrence 2") || !strings.Contains(c, "7.2") {
		t.Error(c)
	}
	// no frames: digits normalised
	e.send(ev("disk 100 full"))
	e.send(ev("disk 7 full"))
	if len(e.f.issues) != 2 || len(e.f.issues[2].Comments) != 1 {
		t.Error("message dedupe")
	}
	e.send(ev("different", "x"))
	if len(e.f.issues) != 3 {
		t.Error("distinct")
	}
}

func TestCommentCapPerIssue(t *testing.T) {
	e := newEnv(t)
	e.s.lim.commentsPerIssueDay = 2
	for i := 0; i < 6; i++ {
		e.send(ev("m", "a"))
	}
	if n := len(e.f.issues[1].Comments); n != 2 {
		t.Errorf("comments %d", n)
	}
	var si *sigInfo
	for _, v := range e.s.st.Sigs {
		si = v
	}
	if si.Count != 6 {
		t.Errorf("count %d", si.Count)
	}
	e.now = e.now.Add(24 * time.Hour)
	e.send(ev("m", "a"))
	if n := len(e.f.issues[1].Comments); n != 3 {
		t.Errorf("next day comments %d", n)
	}
}

func TestClosedReopens(t *testing.T) {
	e := newEnv(t)
	e.send(ev("m", "a"))
	e.f.issues[1].State = "closed"
	u := urlOf(t, e.send(ev("m", "a")))
	if u != "https://github.com/o/r/issues/2" || !strings.Contains(e.f.issues[2].Body, "Seen again after #1") {
		t.Errorf("%s\n%s", u, e.f.issues[2].Body)
	}
	e.send(ev("m", "a"))
	if len(e.f.issues[2].Comments) != 1 || len(e.f.issues[1].Comments) != 0 {
		t.Error("comment went to wrong issue")
	}
}

func TestRepeatedEventID(t *testing.T) {
	e := newEnv(t)
	m := ev("m", "a")
	u1 := urlOf(t, e.send(m))
	calls := e.f.calls
	u2 := urlOf(t, e.send(m))
	if u1 != u2 || e.f.calls != calls || len(e.f.issues[1].Comments) != 0 {
		t.Error("repeat was processed")
	}
}

func TestSuccessEventsDropped(t *testing.T) {
	e := newEnv(t)
	for r := range successTypes {
		m := ev("ok")
		m["tags"].(map[string]any)["report_type"] = r
		w := e.send(m)
		if w.Code != 200 || !strings.Contains(w.Body.String(), `"id"`) || strings.Contains(w.Body.String(), "url") {
			t.Errorf("%s: %d %s", r, w.Code, w.Body)
		}
	}
	if e.f.calls != 0 {
		t.Error("GitHub called")
	}
}

func TestIPLimitAndXFF(t *testing.T) {
	e := newEnv(t)
	e.s.lim.ipPerHour = 10
	post := func(xff string) *httptest.ResponseRecorder {
		b, _ := json.Marshal(ev("x"))
		return e.raw(string(b), goodAuth, xff)
	}
	for i := 0; i < 10; i++ {
		if w := post(fmt.Sprintf("10.0.0.%d, 1.1.1.1", i)); w.Code != 200 {
			t.Fatalf("%d: %d", i, w.Code)
		}
	}
	w := post("spoof, 1.1.1.1")
	if w.Code != 429 || w.Header().Get("Retry-After") == "" {
		t.Errorf("%d %v", w.Code, w.Header())
	}
	if w := post("1.1.1.1, 2.2.2.2"); w.Code != 200 {
		t.Errorf("other ip: %d", w.Code)
	}
	e.now = e.now.Add(61 * time.Minute)
	if w := post("1.1.1.1"); w.Code != 200 {
		t.Errorf("after an hour: %d", w.Code)
	}
}

func TestClientIP(t *testing.T) {
	r := httptest.NewRequest("POST", "/", nil)
	r.RemoteAddr = "192.0.2.9:5"
	if clientIP(r) != "192.0.2.9" {
		t.Error("remote")
	}
	r.Header.Set("X-Forwarded-For", "6.6.6.6, 7.7.7.7 ")
	if clientIP(r) != "7.7.7.7" {
		t.Error("xff")
	}
}

func TestGlobalLimits(t *testing.T) {
	e := newEnv(t)
	e.s.lim.newPerDay = 2
	e.s.lim.commentsPerDay = 1
	e.send(ev("a", "f1"))
	e.send(ev("b", "f2"))
	w := e.send(ev("c", "f3"))
	if w.Code != 429 || w.Header().Get("Retry-After") != "43200" {
		t.Errorf("new: %d %q", w.Code, w.Header().Get("Retry-After"))
	}
	e.send(ev("a", "f1"))
	if w := e.send(ev("a", "f1")); w.Code != 429 {
		t.Errorf("comments: %d", w.Code)
	}
	e.now = e.now.Add(13 * time.Hour)
	if w := e.send(ev("c", "f3")); w.Code != 200 {
		t.Errorf("next day: %d", w.Code)
	}
}

func TestGitHubDownIsNotRemembered(t *testing.T) {
	e := newEnv(t)
	e.f.broken = true
	m := ev("m", "a")
	if w := e.send(m); w.Code != 502 {
		t.Fatal(w.Code)
	}
	e.f.broken = false
	if w := e.send(m); w.Code != 200 || len(e.f.issues) != 1 {
		t.Error("retry failed")
	}
}

func TestStatePersists(t *testing.T) {
	e := newEnv(t)
	m := ev("m", "a")
	e.send(m)
	st, err := loadState(filepath.Join(e.dir, "state.json"))
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := st.seen(strings.ToLower(m["event_id"].(string))); !ok || len(st.Sigs) != 1 {
		t.Error("state lost")
	}
	for i := 0; i < maxSeen+5; i++ {
		st.remember(fmt.Sprintf("%032x", 1000000+i), "u")
	}
	if len(st.Seen) != maxSeen || len(st.idx) != maxSeen {
		t.Error("seen not bounded")
	}
}

func TestHealthz(t *testing.T) {
	e := newEnv(t)
	w := httptest.NewRecorder()
	e.h.ServeHTTP(w, httptest.NewRequest("GET", "/healthz", nil))
	if w.Code != 200 {
		t.Error(w.Code)
	}
}

func TestIPv6By64(t *testing.T) {
	if ipKey("2001:db8::1") != ipKey("2001:db8::ffff") || ipKey("2001:db8::1") == ipKey("2001:db8:0:1::1") {
		t.Error("/64 grouping")
	}
	if ipKey("::ffff:192.0.2.1") != "192.0.2.1" {
		t.Error("mapped v4")
	}
	e := newEnv(t)
	e.s.lim.ipPerHour = 2
	codes := []int{}
	for _, a := range []string{"2001:db8::1", "2001:db8::2", "2001:db8::3", "2001:db8:0:9::1"} {
		b, _ := json.Marshal(ev("x"))
		codes = append(codes, e.raw(string(b), goodAuth, a).Code)
	}
	if fmt.Sprint(codes) != "[200 200 429 200]" {
		t.Error(codes)
	}
}

func TestNewIssuesPerIPAndTable(t *testing.T) {
	e := newEnv(t)
	e.s.lim.newPerIPDay = 3
	for i := 0; i < 3; i++ {
		if w := e.send(ev("m", fmt.Sprint("f", i))); w.Code != 200 {
			t.Fatal(w.Code)
		}
	}
	w := e.send(ev("m", "f9"))
	if w.Code != 429 || w.Header().Get("Retry-After") == "" {
		t.Errorf("per-IP new: %d", w.Code)
	}
	if w := e.send(ev("m", "f0")); w.Code != 200 { // a comment is not a new issue
		t.Errorf("comment: %d", w.Code)
	}
	// sweep keeps an IP that filed today, drops an idle one
	e.s.ipMu.Lock()
	e.s.ips["idle"] = &ipEntry{}
	e.s.ipMu.Unlock()
	e.s.sweep()
	if len(e.s.ips) != 1 {
		t.Errorf("sweep left %d", len(e.s.ips))
	}
	e.now = e.now.Add(25 * time.Hour)
	e.s.sweep()
	if len(e.s.ips) != 0 {
		t.Errorf("sweep left %d", len(e.s.ips))
	}
}

func TestIPTableFull(t *testing.T) {
	e := newEnv(t)
	e.s.lim.ipMapMax, e.s.lim.overflowPerHour = 1, 2
	codes := []int{}
	for _, a := range []string{"1.1.1.1", "2.2.2.2", "3.3.3.3", "4.4.4.4", "1.1.1.1"} {
		b, _ := json.Marshal(ev("x"))
		codes = append(codes, e.raw(string(b), goodAuth, a).Code)
	}
	if fmt.Sprint(codes) != "[200 200 200 429 200]" {
		t.Error(codes)
	}
	if len(e.s.ips) != 1 {
		t.Error("table grew")
	}
}

func TestLockedIssueCountsOnly(t *testing.T) {
	e := newEnv(t)
	e.send(ev("m", "a"))
	for _, code := range []int{403, 422} {
		e.f.commentStatus = code
		if w := e.send(ev("m", "a")); w.Code != 200 || urlOf(t, w) != "https://github.com/o/r/issues/1" {
			t.Errorf("%d: %d", code, w.Code)
		}
	}
	if len(e.f.issues[1].Comments) != 0 || e.s.st.CommentsToday != 0 {
		t.Error("comment counted")
	}
	for _, v := range e.s.st.Sigs {
		if v.Count != 3 {
			t.Errorf("count %d", v.Count)
		}
	}
	e.f.commentStatus = 500
	if w := e.send(ev("m", "a")); w.Code != 502 {
		t.Errorf("500: %d", w.Code)
	}
}

func TestGetIssueErrorsDoNotStick(t *testing.T) {
	e := newEnv(t)
	e.send(ev("m", "a"))
	e.f.getStatus = 400
	for i := 0; i < 4; i++ {
		if w := e.send(ev("m", "a")); w.Code != 502 {
			t.Fatalf("%d: %d", i, w.Code)
		}
	}
	if w := e.send(ev("m", "a")); w.Code != 200 || len(e.f.issues) != 2 {
		t.Errorf("not unstuck: %d, %d issues", w.Code, len(e.f.issues))
	}
}

func TestOpenStateCached(t *testing.T) {
	e := newEnv(t)
	e.send(ev("m", "a"))
	e.send(ev("m", "a")) // GET, now cached
	calls := e.f.calls
	e.send(ev("m", "a")) // comment only
	if e.f.calls != calls+1 {
		t.Errorf("calls %d -> %d", calls, e.f.calls)
	}
	e.now = e.now.Add(6 * time.Minute)
	e.send(ev("m", "a"))
	if e.f.calls != calls+3 {
		t.Errorf("no refetch: %d", e.f.calls)
	}
}

func TestPendingAdoptsLostCreate(t *testing.T) {
	e := newEnv(t)
	e.f.loseCreate = true
	m := ev("m", "a")
	if w := e.send(m); w.Code != 502 {
		t.Fatal(w.Code)
	}
	for _, v := range e.s.st.Sigs {
		if !v.Pending {
			t.Error("not pending")
		}
	}
	e.f.loseCreate = false
	u := urlOf(t, e.send(m))
	if len(e.f.issues) != 1 || u != "https://github.com/o/r/issues/1" || len(e.f.issues[1].Comments) != 1 {
		t.Errorf("%s, %d issues", u, len(e.f.issues))
	}
	for _, v := range e.s.st.Sigs {
		if v.Pending || v.Issue != 1 {
			t.Error("not adopted")
		}
	}
}

func TestPendingWithoutIssueCreates(t *testing.T) {
	e := newEnv(t)
	e.f.broken = true
	e.send(ev("m", "a"))
	e.f.broken = false
	if w := e.send(ev("m", "a")); w.Code != 200 || len(e.f.issues) != 1 {
		t.Error("no create")
	}
}

func TestSaveFailureIs500(t *testing.T) {
	e := newEnv(t)
	e.s.st.path = filepath.Join(e.dir, "missing", "state.json")
	if w := e.send(ev("m", "a")); w.Code != 500 || len(e.f.issues) != 0 {
		t.Errorf("%d, %d issues", w.Code, len(e.f.issues))
	}
}

func TestCorruptStateMovedAside(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "state.json")
	os.WriteFile(p, []byte("{broken"), 0o600)
	st, err := loadState(p)
	if err != nil || len(st.Sigs) != 0 {
		t.Fatal(err)
	}
	m, _ := filepath.Glob(p + ".corrupt-*")
	if len(m) != 1 {
		t.Errorf("backup %v", m)
	}
	if err := st.save(); err != nil {
		t.Error(err)
	}
}

func TestConcurrentSameSignature(t *testing.T) {
	e := newEnv(t)
	var evs []string
	for i := 0; i < 20; i++ {
		b, _ := json.Marshal(ev("m", "a"))
		evs = append(evs, string(b))
	}
	var wg sync.WaitGroup
	for _, b := range evs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if w := e.raw(b, goodAuth, ""); w.Code != 200 {
				t.Error(w.Code)
			}
		}()
	}
	wg.Wait()
	if len(e.f.issues) != 1 {
		t.Errorf("%d issues", len(e.f.issues))
	}
}

func TestProxySecret(t *testing.T) {
	e := newEnv(t)
	e.s.cfg.proxySecret = "s3cret"
	b, _ := json.Marshal(ev("x"))
	post := func(hdr string) int {
		r := httptest.NewRequest("POST", "/api/1/store/", strings.NewReader(string(b)))
		r.RemoteAddr = "192.0.2.1:1234"
		r.Header.Set("X-Sentry-Auth", goodAuth)
		if hdr != "" {
			r.Header.Set("X-Relay-Proxy", hdr)
		}
		w := httptest.NewRecorder()
		e.h.ServeHTTP(w, r)
		return w.Code
	}
	if c := post(""); c != 403 {
		t.Errorf("missing: %d", c)
	}
	if c := post("wrong"); c != 403 {
		t.Errorf("wrong: %d", c)
	}
	if c := post("s3cret"); c != 200 {
		t.Errorf("right: %d", c)
	}
	// healthz stays open for the container healthcheck
	r := httptest.NewRequest("GET", "/healthz", nil)
	w := httptest.NewRecorder()
	e.h.ServeHTTP(w, r)
	if w.Code != 200 {
		t.Errorf("healthz: %d", w.Code)
	}
}

func TestVersionValidation(t *testing.T) {
	e := newEnv(t)
	bad := func(tag, v string) {
		t.Helper()
		m := ev("x")
		m["tags"].(map[string]any)[tag] = v
		if w := e.send(m); w.Code != 400 {
			t.Errorf("%s=%q: %d", tag, v, w.Code)
		}
	}
	bad("app_version", "1.2 # @evil")
	bad("app_version", strings.Repeat("1", 41))
	bad("atlasos_version", "44.2026")
	bad("atlasos_version", "44.20261003 x")
	bad("atlasos_version", "4.20261003")
	for _, v := range []string{"44.20261003", "44.20261003-2", "123.20261003"} {
		m := ev("x")
		m["tags"].(map[string]any)["atlasos_version"] = v
		m["tags"].(map[string]any)["app_version"] = "1.2.3+git~abc_d-1"
		if w := e.send(m); w.Code != 200 {
			t.Errorf("%q: %d", v, w.Code)
		}
	}
	// Clients send "unknown" for a missing value: that must not be refused,
	// or the report would stay pending on the machine forever.
	f := ev("x")
	f["tags"].(map[string]any)["report_type"] = "update-failed"
	f["tags"].(map[string]any)["atlasos_version"] = "unknown"
	f["tags"].(map[string]any)["app_version"] = "unknown"
	if w := e.send(f); w.Code != 200 {
		t.Errorf("unknown versions: %d", w.Code)
	}
}

func TestReleasedClassification(t *testing.T) {
	mk := func(rt, app, os string) *event {
		e := &event{}
		e.Tags.ReportType, e.Tags.AppVersion, e.Tags.AtlasOSVersion = rt, app, os
		return e
	}
	for _, c := range []struct {
		e    *event
		want bool
	}{
		{mk("panic", "1.2.3", ""), true},
		{mk("panic", "1.2+git", ""), false},
		{mk("panic", "unknown", "44.20261003"), false},
		{mk("update-failed", "unknown", "44.20261003"), true},
		{mk("update-failed", "unknown", "unknown"), false},
	} {
		if c.e.released() != c.want {
			t.Errorf("%+v: %v", c.e.Tags, !c.want)
		}
	}
}

func TestReservedQuotaAndWarning(t *testing.T) {
	e := newEnv(t)
	e.s.lim.newPerDay = 4
	var logs strings.Builder
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(os.Stderr) })
	dev := func(i int) int {
		m := ev("m", fmt.Sprint("d", i))
		m["tags"].(map[string]any)["app_version"] = "1.2+gitabc"
		return e.send(m).Code
	}
	if a, b, c := dev(1), dev(2), dev(3); a != 200 || b != 200 || c != 429 {
		t.Fatalf("unreleased: %d %d %d", a, b, c)
	}
	if n := strings.Count(logs.String(), "unreleased versions"); n != 1 {
		t.Errorf("unreleased warnings: %d", n)
	}
	for i := 1; i <= 2; i++ {
		if w := e.send(ev("m", fmt.Sprint("r", i))); w.Code != 200 {
			t.Fatalf("released %d: %d", i, w.Code)
		}
	}
	for i := 3; i <= 5; i++ {
		if w := e.send(ev("m", fmt.Sprint("r", i))); w.Code != 429 {
			t.Fatalf("over quota: %d", w.Code)
		}
	}
	if n := strings.Count(logs.String(), "WARNING: daily new-issue quota"); n != 1 {
		t.Errorf("warning lines: %d", n)
	}
	e.now = e.now.Add(13 * time.Hour)
	if w := e.send(ev("m", "r9")); w.Code != 200 {
		t.Errorf("next day: %d", w.Code)
	}
}

func TestConfigNeedsKey(t *testing.T) {
	if err := (config{}).validate(); err == nil {
		t.Error("empty SENTRY_KEY accepted")
	}
	if err := (config{key: "k"}).validate(); err != nil {
		t.Error(err)
	}
	if err := (config{key: "k", proxySecretSet: true, proxySecret: ""}).validate(); err == nil {
		t.Error("blank proxy secret accepted")
	}
	if err := (config{key: "k", proxySecretSet: true, proxySecret: "short"}).validate(); err == nil {
		t.Error("short proxy secret accepted")
	}
	if err := (config{key: "k", proxySecretSet: true, proxySecret: strings.Repeat("a", 32)}).validate(); err != nil {
		t.Error(err)
	}
}

func TestSearchIgnoresDecoys(t *testing.T) {
	e := newEnv(t)
	e.f.loseCreate = true
	m := ev("m", "a")
	e.send(m) // 502; issue 1 exists and is the real one
	e.f.loseCreate = false
	sig := ""
	for k := range e.s.st.Sigs {
		sig = k
	}
	marker := "<!-- atlas-crash-signature: " + sig + " -->"
	// A decoy opened by someone else: wrong label.
	e.f.issues[2] = &fIssue{"open", "decoy", "text\n" + marker + "\n", []string{"bug"}, nil}
	// A decoy with the crash label but the marker inside a fence, not last.
	e.f.issues[3] = &fIssue{"open", "decoy2", "```\n" + marker + "\n```\nmore", []string{"crash"}, nil}
	// The lost create is relabelled, so only decoys match: a new issue is filed.
	e.f.issues[1].Labels = []string{"bug"}
	if w := e.send(m); w.Code != 200 || len(e.f.issues) != 4 {
		t.Fatalf("decoy adopted: %d, %d issues", w.Code, len(e.f.issues))
	}
	if len(e.f.issues[1].Comments)+len(e.f.issues[2].Comments)+len(e.f.issues[3].Comments) != 0 {
		t.Error("comment landed on a decoy")
	}
}

func TestPerSlash48(t *testing.T) {
	e := newEnv(t)
	e.s.lim.newPer48Day = 2
	post := func(ip string, i int) int {
		b, _ := json.Marshal(ev("m", fmt.Sprint("g", i)))
		return e.raw(string(b), goodAuth, ip).Code
	}
	// different /64s, same /48
	if a, b, c := post("2001:db8:1:1::1", 1), post("2001:db8:1:2::1", 2), post("2001:db8:1:3::1", 3); a != 200 || b != 200 || c != 429 {
		t.Errorf("/48: %d %d %d", a, b, c)
	}
	if c := post("2001:db8:2::1", 4); c != 200 {
		t.Errorf("other /48: %d", c)
	}
}

func TestRefundAcrossDayKeepsNewCounter(t *testing.T) {
	e := newEnv(t)
	e.s.st.rollDay(e.now)
	e.s.st.NewToday = 0
	e.f.broken = true
	e.send(ev("m", "a")) // fails, refunds
	if e.s.st.NewToday != 0 {
		t.Errorf("counter %d", e.s.st.NewToday)
	}
}

func TestLoadConfigBlankProxySecretCountsAsSet(t *testing.T) {
	t.Setenv("RELAY_PROXY_SECRET", "")
	c := loadConfig()
	if !c.proxySecretSet {
		t.Fatal("a blank RELAY_PROXY_SECRET must count as set, so validate refuses it")
	}
	if err := (config{key: "k", proxySecretSet: c.proxySecretSet, proxySecret: c.proxySecret}).validate(); err == nil {
		t.Fatal("a blank RELAY_PROXY_SECRET was accepted")
	}
}

func TestKey48OnlyGroupsSlash64(t *testing.T) {
	for key, want := range map[string]string{
		"2001:db8:1:2::/64": "48:2001:db8:1::/48",
		"2001:db8::/32":     "",
		"2001:db8:1::/48":   "",
		"192.0.2.1":         "",
		"not an ip":         "",
	} {
		if got := key48(key); got != want {
			t.Errorf("key48(%q) = %q, want %q", key, got, want)
		}
	}
}

func (f *fakeGH) fail(w http.ResponseWriter, code int) {
	for k, v := range f.replyHdr {
		w.Header()[k] = v
	}
	body := f.replyBody
	if body == "" {
		body = "no"
	}
	http.Error(w, body, code)
}

func TestRateLimit403IsNotGoneOrLocked(t *testing.T) {
	e := newEnv(t)
	e.send(ev("m", "a")) // issue 1, open
	e.now = e.now.Add(10 * time.Minute) // past the open-state cache
	e.f.getStatus = 403
	e.f.replyBody = "You have exceeded a secondary rate limit"
	e.f.replyHdr = http.Header{"Retry-After": {"77"}}
	w := e.send(ev("m", "a"))
	if w.Code != 503 || w.Header().Get("Retry-After") != "77" || len(e.f.issues) != 1 {
		t.Fatalf("rate limited get: %d %q, %d issues", w.Code, w.Header().Get("Retry-After"), len(e.f.issues))
	}
	// A real 403 on the same call: the issue is hidden, so it is gone.
	e.f.replyBody, e.f.replyHdr = "Resource not accessible", nil
	if w := e.send(ev("m", "a")); w.Code != 200 || len(e.f.issues) != 2 {
		t.Errorf("real 403: %d, %d issues", w.Code, len(e.f.issues))
	}
}

func TestRateLimitedCommentIsNotLocked(t *testing.T) {
	e := newEnv(t)
	e.send(ev("m", "a"))
	e.f.commentStatus = 403
	e.f.replyHdr = http.Header{"X-Ratelimit-Remaining": {"0"}}
	w := e.send(ev("m", "a"))
	if w.Code != 503 || w.Header().Get("Retry-After") == "" {
		t.Fatalf("rate limited comment: %d", w.Code)
	}
	if e.s.st.CommentsToday != 0 {
		t.Errorf("comment not refunded: %d", e.s.st.CommentsToday)
	}
	e.f.replyHdr = nil // a plain 403: locked, counted
	if w := e.send(ev("m", "a")); w.Code != 200 {
		t.Errorf("locked: %d", w.Code)
	}
}

func TestOutageNeverMakesGone(t *testing.T) {
	e := newEnv(t)
	e.send(ev("m", "a"))
	e.now = e.now.Add(10 * time.Minute)
	e.f.getStatus = 503
	for i := 0; i < 8; i++ {
		if w := e.send(ev("m", "a")); w.Code != 502 {
			t.Fatalf("%d: %d", i, w.Code)
		}
	}
	e.f.getStatus = 0
	if w := e.send(ev("m", "a")); w.Code != 200 || len(e.f.issues) != 1 {
		t.Errorf("after outage: %d, %d issues", w.Code, len(e.f.issues))
	}
}

func TestSaveFailureAfterCreateIs200(t *testing.T) {
	e := newEnv(t)
	e.f.onCreate = func() {
		e.s.mu.Lock()
		e.s.st.path = filepath.Join(e.dir, "missing", "state.json")
		e.s.mu.Unlock()
	}
	if w := e.send(ev("m", "a")); w.Code != 200 || len(e.f.issues) != 1 {
		t.Errorf("%d, %d issues", w.Code, len(e.f.issues))
	}
}

func TestLockWaitBounded(t *testing.T) {
	e := newEnv(t)
	e.s.lockWait = 50 * time.Millisecond
	m := ev("m", "a")
	var evt event
	b, _ := json.Marshal(m)
	json.Unmarshal(b, &evt)
	evt.sanitize()
	unlock, err := e.s.lockSig(context.Background(), signature(&evt))
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	w := e.send(m)
	if w.Code != 503 || w.Header().Get("Retry-After") == "" {
		t.Errorf("%d %v", w.Code, w.Header())
	}
}

func TestClientDisconnectDoesNotCancelCreate(t *testing.T) {
	e := newEnv(t)
	b, _ := json.Marshal(ev("m", "a"))
	r := httptest.NewRequest("POST", "/api/1/store/", strings.NewReader(string(b)))
	r.RemoteAddr = "192.0.2.1:1"
	r.Header.Set("X-Sentry-Auth", goodAuth)
	ctx, cancel := context.WithCancel(r.Context())
	cancel() // the client is already gone
	w := httptest.NewRecorder()
	e.h.ServeHTTP(w, r.WithContext(ctx))
	if w.Code != 200 || len(e.f.issues) != 1 {
		t.Errorf("%d, %d issues", w.Code, len(e.f.issues))
	}
}

func TestCommentRefundAcrossDay(t *testing.T) {
	e := newEnv(t)
	e.send(ev("m", "a"))
	e.f.commentStatus = 500
	e.f.onComment = func() {
		e.s.mu.Lock()
		e.now = e.now.Add(24 * time.Hour)
		e.s.st.rollDay(e.now)
		e.s.st.CommentsToday = 3
		e.s.mu.Unlock()
	}
	e.send(ev("m", "a"))
	if e.s.st.CommentsToday != 3 {
		t.Errorf("refunded into the new day: %d", e.s.st.CommentsToday)
	}
}

func TestShutdownWaitsForInFlight(t *testing.T) {
	e := newEnv(t)
	started, release := make(chan struct{}), make(chan struct{})
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(started)
		<-release
		w.Write([]byte("done"))
	})
	srv := &http.Server{Handler: h}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	stop := make(chan struct{})
	ret := make(chan error, 1)
	go func() { ret <- runServer(srv, ln, e.s, stop, 5*time.Second) }()
	got := make(chan string, 1)
	go func() {
		resp, err := http.Get("http://" + ln.Addr().String() + "/")
		if err != nil {
			got <- err.Error()
			return
		}
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		got <- string(b)
	}()
	<-started
	close(stop)
	select {
	case <-ret:
		t.Fatal("returned with a request in flight")
	case <-time.After(200 * time.Millisecond):
	}
	close(release)
	if v := <-got; v != "done" {
		t.Errorf("reply %q", v)
	}
	if err := <-ret; err != nil {
		t.Error(err)
	}
}

func TestStateBackupAndStaleTemp(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "state.json")
	st, _ := loadState(p)
	st.Sigs["aa"] = &sigInfo{Issue: 7, Last: "2026-10-01"}
	st.Day = "2026-10-01"
	if err := st.save(); err != nil {
		t.Fatal(err)
	}
	st.Sigs["bb"] = &sigInfo{Issue: 8, Last: "2026-10-01"}
	if err := st.save(); err != nil { // the first state becomes the .bak
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(dir, ".state-stale"), []byte("x"), 0o600)
	os.WriteFile(p, []byte("{broken"), 0o600)
	got, err := loadState(p)
	if err != nil {
		t.Fatal(err)
	}
	if got.Sigs["aa"] == nil || got.Sigs["bb"] != nil {
		t.Errorf("did not use the previous state: %v", got.Sigs)
	}
	if _, err := os.Stat(filepath.Join(dir, ".state-stale")); err == nil {
		t.Error("stale temp file left")
	}
	if m, _ := filepath.Glob(p + ".corrupt-*"); len(m) != 1 {
		t.Error("corrupt file not moved aside")
	}
}

func TestOldSigsPruned(t *testing.T) {
	st := &state{Day: "2026-10-01", Sigs: map[string]*sigInfo{
		"old": {Last: "2026-03-01"}, "new": {Last: "2026-09-01"}, "legacy": {}}}
	st.rollDay(time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC))
	if st.Sigs["old"] != nil || st.Sigs["new"] == nil || st.Sigs["legacy"] == nil || st.Sigs["legacy"].Last == "" {
		t.Errorf("%v", st.Sigs)
	}
}

func TestUnreadableStateIsNotSetAside(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "state.json")
	os.WriteFile(p, []byte(`{"day":"x"}`), 0o600)
	os.Chmod(p, 0)
	defer os.Chmod(p, 0o600)
	if f, err := os.Open(p); err == nil { // running as root: can't make it unreadable
		f.Close()
		t.Skip("file still readable")
	}
	if _, err := loadState(p); err == nil {
		t.Fatal("started on an unreadable state file")
	}
	if m, _ := filepath.Glob(p + ".corrupt-*"); len(m) != 0 {
		t.Error("good file renamed")
	}
	if _, err := os.Stat(p); err != nil {
		t.Error("state file gone")
	}
}

func TestExitSavesOnlyWhenDirty(t *testing.T) {
	run := func(e *rig) {
		stop := make(chan struct{})
		close(stop)
		ln, _ := net.Listen("tcp", "127.0.0.1:0")
		if err := runServer(&http.Server{}, ln, e.s, stop, time.Second); err != nil {
			t.Fatal(err)
		}
	}
	e := newEnv(t)
	e.send(ev("m", "a"))
	e.send(ev("n", "b")) // .bak now holds the state after the first
	p := filepath.Join(e.dir, "state.json")
	before, _ := os.ReadFile(p + ".bak")
	run(e)
	if after, _ := os.ReadFile(p + ".bak"); string(after) != string(before) {
		t.Error("clean exit rotated .bak")
	}
	e.s.st.dirty = true
	run(e)
	if after, _ := os.ReadFile(p + ".bak"); string(after) == string(before) {
		t.Error("dirty exit did not save")
	}
}

func TestRejectedTokenIsNotGone(t *testing.T) {
	e := newEnv(t)
	e.send(ev("m", "a"))
	e.now = e.now.Add(10 * time.Minute)
	e.f.getStatus = 401
	for i := 0; i < 8; i++ {
		w := e.send(ev("m", "a"))
		if w.Code != 503 || w.Header().Get("Retry-After") == "" {
			t.Fatalf("%d: %d", i, w.Code)
		}
	}
	e.f.getStatus = 0
	if w := e.send(ev("m", "a")); w.Code != 200 || len(e.f.issues) != 1 {
		t.Errorf("after: %d, %d issues", w.Code, len(e.f.issues))
	}
}

func TestOpenSigsKeptLonger(t *testing.T) {
	st := &state{Day: "2026-10-01", Sigs: map[string]*sigInfo{
		"open": {Last: "2026-03-01", Open: true}, "closed": {Last: "2026-03-01"},
		"ancient": {Last: "2025-01-01", Open: true}}}
	st.rollDay(time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC))
	if st.Sigs["open"] == nil || st.Sigs["closed"] != nil || st.Sigs["ancient"] != nil {
		t.Errorf("%v", st.Sigs)
	}
}

func TestCorruptStateWithUnreadableBakFailsStart(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "state.json")
	os.WriteFile(p, []byte(`{not json`), 0o600)
	os.WriteFile(p+".bak", []byte(`{"day":"x"}`), 0o600)
	os.Chmod(p+".bak", 0)
	defer os.Chmod(p+".bak", 0o600)
	if f, err := os.Open(p + ".bak"); err == nil { // running as root
		f.Close()
		t.Skip("file still readable")
	}
	if _, err := loadState(p); err == nil {
		t.Fatal("started empty although the previous state could not be read")
	}
	if _, err := os.Stat(p); err != nil {
		t.Error("corrupt state file moved before the .bak was read")
	}
}

func TestCorruptStateFallsBackToBak(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "state.json")
	os.WriteFile(p, []byte(`{not json`), 0o600)
	os.WriteFile(p+".bak", []byte(`{"day":"2026-10-01"}`), 0o600)
	st, err := loadState(p)
	if err != nil {
		t.Fatal(err)
	}
	if st.Day != "2026-10-01" {
		t.Errorf("day %q, want the .bak's", st.Day)
	}
	if m, _ := filepath.Glob(p + ".corrupt-*"); len(m) != 1 {
		t.Error("corrupt file not set aside")
	}
}
