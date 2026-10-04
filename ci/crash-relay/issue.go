package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"regexp"
	"strings"
	"unicode"
)

// Reports from the client are untrusted: every string is cleaned and capped
// on the way in, and goes into the issue only as inline code, a fenced block
// or a neutralised title.

type frame struct {
	Function string `json:"function"`
	Addr     string `json:"instruction_addr"`
	Package  string `json:"package"`
}

type event struct {
	EventID     string `json:"event_id"`
	Message     string `json:"message"`
	Release     string `json:"release"`
	Environment string `json:"environment"`
	Tags        struct {
		App             string `json:"app"`
		AppVersion      string `json:"app_version"`
		Category        string `json:"category"`
		AtlasOSVersion  string `json:"atlasos_version"`
		Channel         string `json:"channel"`
		PreviousVersion string `json:"previous_version"`
		Kernel          string `json:"kernel"`
		GPU             string `json:"gpu"`
		GPUDriver       string `json:"gpu_driver"`
		ReportType      string `json:"report_type"`
	} `json:"tags"`
	Contexts struct {
		Device struct {
			CPU        string  `json:"cpu"`
			MemorySize float64 `json:"memory_size"`
			FreeMemory float64 `json:"free_memory"`
		} `json:"device"`
		Runtime struct {
			UptimeSecs float64 `json:"uptime_secs"`
		} `json:"runtime"`
	} `json:"contexts"`
	Exception struct {
		Values []struct {
			Stacktrace struct {
				Frames []frame `json:"frames"`
			} `json:"stacktrace"`
		} `json:"values"`
	} `json:"exception"`

	frames []frame
}

var successTypes = map[string]bool{
	"update-staged": true, "update-applied": true, "rollback-requested": true,
	"rollback-applied": true, "channel-switched": true,
	"channel-switch-applied": true, "health-check-passed": true,
}

var failureTypes = map[string]bool{
	"update-failed": true, "rollback-failed": true, "channel-switch-failed": true,
	"automatic-rollback": true, "health-check-failed": true,
}

// reportTypes are the ones filed as issues: crashes and the failure events.
func reportType(t string) bool {
	return t == "panic" || t == "fatal" || t == "coredump" || failureTypes[t]
}

var (
	appVersionRe = regexp.MustCompile(`^[0-9A-Za-z.+~_-]{1,40}$`)
	osVersionRe  = regexp.MustCompile(`^[0-9]{2,3}\.[0-9]{8}(-[0-9]+)?$`)
	// releasedRe is a plain release number; dev and git builds don't match and
	// share only part of the daily new-issue quota.
	releasedRe = regexp.MustCompile(`^[0-9]{1,4}\.[0-9]{1,4}(\.[0-9]{1,4})?$`)
)

// versionsOK checks the two version tags that go into titles. Clients send
// "unknown" for a missing value, so empty and "unknown" pass; anything else
// must match its pattern.
func (e *event) versionsOK() bool {
	t := &e.Tags
	if v := t.AppVersion; v != "" && v != "unknown" && !appVersionRe.MatchString(v) {
		return false
	}
	if v := t.AtlasOSVersion; v != "" && v != "unknown" && !osVersionRe.MatchString(v) {
		return false
	}
	return true
}

// released: a plain release number, or for update-problem reports (which may
// carry no app_version) a valid AtlasOS version.
func (e *event) released() bool {
	if releasedRe.MatchString(e.Tags.AppVersion) {
		return true
	}
	return failureTypes[e.Tags.ReportType] && osVersionRe.MatchString(e.Tags.AtlasOSVersion)
}

var appName = regexp.MustCompile(`^[A-Za-z0-9._/+-]{1,100}$`)

const maxFrames = 200

// clean drops control and format characters (bidi overrides, zero-width ones;
// newline and tab stay when keepNL) and caps the length in runes.
func clean(s string, max int, keepNL bool) string {
	var b strings.Builder
	n := 0
	for _, r := range s {
		if n >= max {
			break
		}
		switch {
		case keepNL && (r == '\n' || r == '\t'):
		case unicode.IsControl(r) || unicode.Is(unicode.Cf, r) || r == 0x2028 || r == 0x2029:
			continue
		}
		b.WriteRune(r)
		n++
	}
	return b.String()
}

func (e *event) sanitize() {
	t := &e.Tags
	for _, p := range []*string{&t.App, &t.AppVersion, &t.Category, &t.AtlasOSVersion,
		&t.Channel, &t.PreviousVersion, &t.ReportType, &e.Release, &e.Environment} {
		*p = clean(*p, 100, false)
	}
	for _, p := range []*string{&t.Kernel, &t.GPU, &t.GPUDriver, &e.Contexts.Device.CPU} {
		*p = clean(*p, 200, false)
	}
	e.Message = clean(e.Message, 4000, true)
	if len(e.Exception.Values) > 0 {
		fr := e.Exception.Values[0].Stacktrace.Frames
		if len(fr) > maxFrames {
			fr = fr[len(fr)-maxFrames:]
		}
		for _, f := range fr {
			e.frames = append(e.frames, frame{clean(f.Function, 300, false),
				clean(f.Addr, 64, false), clean(f.Package, 200, false)})
		}
	}
}

var digits = regexp.MustCompile(`[0-9]+`)

func signature(e *event) string {
	h := sha256.New()
	fmt.Fprintf(h, "%s\n%s\n", e.Tags.App, e.Tags.ReportType)
	var names []string
	for i := len(e.frames) - 1; i >= 0 && len(names) < 5; i-- {
		names = append(names, e.frames[i].Function)
	}
	if strings.Join(names, "") == "" {
		fmt.Fprint(h, "msg\n", digits.ReplaceAllString(e.Message, "N"))
	} else {
		fmt.Fprint(h, "frames\n", strings.Join(names, "\n"))
	}
	return hex.EncodeToString(h.Sum(nil))
}

// inline renders a short value as inline code. Newlines, pipes and backticks
// are removed, so it can't leave the table cell or the code span.
func inline(s string) string {
	s = strings.NewReplacer("\n", "", "\r", "", "|", "", "`", "").Replace(s)
	if strings.TrimSpace(s) == "" {
		s = "unknown"
	}
	return "`" + s + "`"
}

// fence wraps free text in a code fence longer than any backtick run in it.
func fence(s string) string {
	longest, run := 0, 0
	for _, r := range s {
		if r == '`' {
			run++
			if run > longest {
				longest = run
			}
		} else {
			run = 0
		}
	}
	f := strings.Repeat("`", max(3, longest+1))
	return f + "\n" + s + "\n" + f
}

var titleNeutral = strings.NewReplacer("@", "@\u200b", "#", "#\u200b")

func titleText(s string) string {
	s = strings.Join(strings.Fields(clean(s, 200, true)), " ")
	if s == "" {
		s = "unknown"
	}
	return titleNeutral.Replace(s)
}

func capRunes(s string, n int) string {
	if r := []rune(s); len(r) > n {
		return string(r[:n])
	}
	return s
}

func title(e *event) string {
	t := &e.Tags
	var s string
	if failureTypes[t.ReportType] {
		s = fmt.Sprintf("Update problem: %s on AtlasOS %s", titleText(t.ReportType), titleText(t.AtlasOSVersion))
	} else {
		s = fmt.Sprintf("Crash: %s %s (%s)", titleText(t.App), titleText(t.AppVersion), titleText(t.ReportType))
	}
	return capRunes(s, 200)
}

func row(k, v string) string { return "| " + k + " | " + inline(v) + " |\n" }

func versionsTable(e *event) string {
	t := &e.Tags
	var b strings.Builder
	b.WriteString("| Field | Value |\n|---|---|\n")
	b.WriteString(row("App", t.App))
	b.WriteString(row("App version", t.AppVersion))
	b.WriteString(row("Report type", t.ReportType))
	b.WriteString(row("Category", t.Category))
	b.WriteString(row("AtlasOS", t.AtlasOSVersion))
	b.WriteString(row("Previous version", t.PreviousVersion))
	b.WriteString(row("Channel", t.Channel))
	b.WriteString(row("Kernel", t.Kernel))
	b.WriteString(row("GPU", t.GPU))
	b.WriteString(row("GPU driver", t.GPUDriver))
	return b.String()
}

func issueBody(e *event, sig string, prev int) string {
	var b strings.Builder
	b.WriteString("Filed automatically from an Atlas Updater crash report.\n\n")
	if prev > 0 {
		fmt.Fprintf(&b, "Seen again after #%d, which is closed.\n\n", prev)
	}
	b.WriteString(versionsTable(e))
	d := &e.Contexts.Device
	b.WriteString(row("CPU", d.CPU))
	b.WriteString(row("Memory", fmt.Sprintf("%.0f MiB total, %.0f MiB free", d.MemorySize/1048576, d.FreeMemory/1048576)))
	b.WriteString(row("Uptime", fmt.Sprintf("%.0f s", e.Contexts.Runtime.UptimeSecs)))
	b.WriteString("\n**Message**\n\n")
	b.WriteString(fence(e.Message) + "\n")
	if n := len(e.frames); n > 0 {
		b.WriteString("\n**Stack trace** (oldest call first, last 40 frames)\n\n")
		var tr strings.Builder
		for i := max(0, n-40); i < n; i++ {
			f := e.frames[i]
			fmt.Fprintf(&tr, "%s  %s  %s\n", f.Addr, f.Function, f.Package)
		}
		b.WriteString(fence(strings.TrimRight(tr.String(), "\n")) + "\n")
	}
	fmt.Fprintf(&b, "\n<!-- atlas-crash-signature: %s -->\n", sig)
	return b.String()
}

func commentBody(e *event, occurrence int) string {
	return fmt.Sprintf("Seen again (occurrence %d).\n\n%s", occurrence, versionsTable(e))
}
