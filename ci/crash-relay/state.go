package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"
)

const (
	maxSeen         = 10000
	sigKeepDays     = 180
	sigKeepOpenDays = 365 // for an issue last known open
)

type sigInfo struct {
	Issue       int    `json:"issue"`
	URL         string `json:"url"`
	Count       int    `json:"count"`
	CommentDay  string `json:"comment_day"`
	CommentsDay int    `json:"comments_day"`
	// Pending: the issue is being created and its number is not known yet.
	// Prev is the closed issue this one follows.
	Pending bool `json:"pending,omitempty"`
	Prev    int  `json:"prev,omitempty"`
	// Last is the UTC date of the last report; old ones are pruned.
	Last string `json:"last,omitempty"`
	// Open: the issue was last known open. Such a signature is kept longer.
	Open bool `json:"open,omitempty"`

	// Memory only.
	Fails  int       `json:"-"`
	OpenAt time.Time `json:"-"`
}

type seenEntry struct {
	ID  string `json:"id"`
	URL string `json:"url"`
}

type state struct {
	Day           string              `json:"day"`
	NewToday      int                 `json:"new_today"`
	CommentsToday int                 `json:"comments_today"`
	NewUnrelToday int                 `json:"new_unreleased_today"`
	WarnDay       string              `json:"warn_day,omitempty"`
	WarnUnrelDay  string              `json:"warn_unreleased_day,omitempty"`
	Sigs          map[string]*sigInfo `json:"sigs"`
	Seen          []seenEntry         `json:"seen"`

	idx   map[string]string
	path  string
	dirty bool // a save failed since the last good one
}

func readState(path string) (*state, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	st := &state{}
	if err := json.Unmarshal(b, st); err != nil {
		return nil, &parseError{err}
	}
	return st, nil
}

// parseError: the file was read but is not valid state. Only this, never an
// I/O error, makes loadState set a file aside.
type parseError struct{ err error }

func (e *parseError) Error() string { return "state file is not valid JSON: " + e.err.Error() }
func (e *parseError) Unwrap() error { return e.err }

func loadState(path string) (*state, error) {
	dir := filepath.Dir(path)
	// Temp files left by a crash mid-save.
	if old, _ := filepath.Glob(filepath.Join(dir, ".state-*")); len(old) > 0 {
		for _, f := range old {
			_ = os.Remove(f)
		}
	}
	_ = os.Remove(path + ".bak.tmp")
	st, err := readState(path)
	switch {
	case err == nil:
	case errors.Is(err, os.ErrNotExist):
		st = &state{}
	default:
		var pe *parseError
		if !errors.As(err, &pe) {
			// A read error (EIO, EACCES) says nothing about the contents:
			// keep the file and fail, so the container restarts and retries.
			return nil, fmt.Errorf("cannot read %s, leaving it alone: %w", path, err)
		}
		// The previous state, read before anything moves: a .bak that can't
		// be read (as opposed to a missing or corrupt one) fails the start
		// too, rather than starting empty on a transient error.
		prev, perr := readState(path + ".bak")
		if perr != nil && !errors.Is(perr, os.ErrNotExist) && !errors.As(perr, &pe) {
			return nil, fmt.Errorf("%s is corrupt and cannot read %s.bak, leaving both alone: %w", path, filepath.Base(path), perr)
		}
		bak := path + ".corrupt-" + time.Now().UTC().Format("20060102T150405Z")
		if rerr := os.Rename(path, bak); rerr != nil {
			return nil, rerr
		}
		if perr == nil {
			log.Printf("state file is corrupt, moved to %s, using the previous state", filepath.Base(bak))
			st = prev
		} else {
			log.Printf("state file is corrupt, moved to %s, starting empty", filepath.Base(bak))
			st = &state{}
		}
	}
	st.path = path
	if st.Sigs == nil {
		st.Sigs = map[string]*sigInfo{}
	}
	st.idx = make(map[string]string, len(st.Seen))
	for _, e := range st.Seen {
		st.idx[e.ID] = e.URL
	}
	return st, nil
}

// rollDay resets the daily counters when the UTC date changes.
func (st *state) rollDay(now time.Time) {
	if d := now.UTC().Format("2006-01-02"); st.Day != d {
		st.Day, st.NewToday, st.CommentsToday, st.NewUnrelToday = d, 0, 0, 0
		cut := now.UTC().AddDate(0, 0, -sigKeepDays).Format("2006-01-02")
		cutOpen := now.UTC().AddDate(0, 0, -sigKeepOpenDays).Format("2006-01-02")
		for k, si := range st.Sigs {
			if si.Last == "" {
				si.Last = d // from an older state file: start the clock now
			} else if si.Last < cut && (!si.Open || si.Last < cutOpen) {
				delete(st.Sigs, k)
			}
		}
	}
}

func (st *state) seen(id string) (string, bool) {
	u, ok := st.idx[id]
	return u, ok
}

func (st *state) remember(id, url string) {
	if _, ok := st.idx[id]; ok {
		return
	}
	st.idx[id] = url
	st.Seen = append(st.Seen, seenEntry{id, url})
	for len(st.Seen) > maxSeen {
		delete(st.idx, st.Seen[0].ID)
		st.Seen = st.Seen[1:]
	}
}

// save writes the state atomically: temp file, fsync, rename.
func (st *state) save() (err error) {
	defer func() { st.dirty = err != nil }()
	b, err := json.Marshal(st)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(st.path), ".state-*")
	if err != nil {
		return err
	}
	name := f.Name()
	if _, err = f.Write(b); err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		// Keep the state being replaced as state.json.bak (a hard link, so
		// there is never a moment without a state file).
		tmp := st.path + ".bak.tmp"
		_ = os.Remove(tmp)
		if os.Link(st.path, tmp) == nil {
			_ = os.Rename(tmp, st.path+".bak")
		}
		err = os.Rename(name, st.path)
	}
	if err == nil {
		if d, derr := os.Open(filepath.Dir(st.path)); derr == nil {
			err = d.Sync()
			d.Close()
		}
	}
	if err != nil {
		_ = os.Remove(name)
	}
	return err
}

