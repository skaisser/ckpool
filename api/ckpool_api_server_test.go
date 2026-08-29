package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// useTempUserLogDir points userLogPath at a fresh temp dir for one test and
// restores it afterwards.
func useTempUserLogDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	orig := userLogPath
	userLogPath = dir
	t.Cleanup(func() { userLogPath = orig })
	return dir
}

func writeUserFile(t *testing.T, dir, name string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(`{"shares":1}`), 0o644); err != nil {
		t.Fatalf("writing fixture %q: %v", name, err)
	}
}

func TestResolveUserFile(t *testing.T) {
	const bare = "qzxq7lc575az8tw357ck50wdl7cmn4lc2v9kp3rz4u"

	tests := []struct {
		name         string
		files        []string
		query        string
		wantFound    bool
		wantResolved string
	}{
		{
			name:         "exact prefixed hit",
			files:        []string{"bitcoincash:" + bare},
			query:        "bitcoincash:" + bare,
			wantFound:    true,
			wantResolved: "bitcoincash:" + bare,
		},
		{
			name:         "exact bare hit",
			files:        []string{bare},
			query:        bare,
			wantFound:    true,
			wantResolved: bare,
		},
		{
			name:         "prefixed query falls back to bare file",
			files:        []string{bare},
			query:        "bitcoincash:" + bare,
			wantFound:    true,
			wantResolved: bare,
		},
		{
			name:         "bare query falls back to prefixed file",
			files:        []string{"bitcoincash:" + bare},
			query:        bare,
			wantFound:    true,
			wantResolved: "bitcoincash:" + bare,
		},
		{
			name:         "bare query reaches testnet prefix",
			files:        []string{"bchtest:" + bare},
			query:        bare,
			wantFound:    true,
			wantResolved: "bchtest:" + bare,
		},
		{
			name:         "exact beats fallback when both exist (prefixed query)",
			files:        []string{"bitcoincash:" + bare, bare},
			query:        "bitcoincash:" + bare,
			wantFound:    true,
			wantResolved: "bitcoincash:" + bare,
		},
		{
			name:         "exact beats fallback when both exist (bare query)",
			files:        []string{"bitcoincash:" + bare, bare},
			query:        bare,
			wantFound:    true,
			wantResolved: bare,
		},
		{
			name:      "miss",
			files:     nil,
			query:     "bitcoincash:" + bare,
			wantFound: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := useTempUserLogDir(t)
			for _, f := range tt.files {
				writeUserFile(t, dir, f)
			}
			path, resolved, found := resolveUserFile(tt.query)
			if found != tt.wantFound {
				t.Fatalf("found = %v, want %v", found, tt.wantFound)
			}
			if !found {
				return
			}
			if resolved != tt.wantResolved {
				t.Errorf("resolved = %q, want %q", resolved, tt.wantResolved)
			}
			if want := filepath.Join(dir, tt.wantResolved); path != want {
				t.Errorf("path = %q, want %q", path, want)
			}
		})
	}
}

func TestResolveUserFileCannotEscapeUsersDir(t *testing.T) {
	dir := useTempUserLogDir(t)

	// A real file OUTSIDE the users dir that traversal would reach if
	// sanitization ever regressed.
	outside := filepath.Join(filepath.Dir(dir), "passwd")
	if err := os.WriteFile(outside, []byte("secret"), 0o644); err != nil {
		t.Fatalf("writing outside fixture: %v", err)
	}

	for _, query := range []string{
		"../passwd",
		"../../etc/passwd",
		"bitcoincash:../passwd",
		"bchreg:../../passwd",
		"sub/../../passwd",
	} {
		if path, _, found := resolveUserFile(query); found {
			t.Errorf("query %q escaped the users dir: resolved to %q", query, path)
		}
	}

	// filepath.Base collapses a traversal to its last element, so the SAME
	// basename inside the dir must still resolve — proving containment, not
	// blanket rejection.
	writeUserFile(t, dir, "passwd")
	if _, resolved, found := resolveUserFile("../passwd"); !found || resolved != "passwd" {
		t.Errorf("in-dir basename should resolve after sanitization; found=%v resolved=%q", found, resolved)
	}
}

func TestHandleUserFileFallback(t *testing.T) {
	dir := useTempUserLogDir(t)
	const bare = "qzxq7lc575az8tw357ck50wdl7cmn4lc2v9kp3rz4u"
	writeUserFile(t, dir, "bitcoincash:"+bare)

	get := func(user string) UserFileResponse {
		t.Helper()
		req := httptest.NewRequest(http.MethodGet, "/user-file?user="+user, nil)
		rec := httptest.NewRecorder()
		handleUserFile(rec, req)
		var resp UserFileResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("decoding response: %v", err)
		}
		return resp
	}

	// Bare query resolves the prefixed file and reports the canonical name.
	resp := get(bare)
	if resp.Error != "" {
		t.Fatalf("unexpected error: %q", resp.Error)
	}
	if resp.Username != "bitcoincash:"+bare {
		t.Errorf("username = %q, want canonical %q", resp.Username, "bitcoincash:"+bare)
	}
	if resp.Content == nil {
		t.Error("content should be populated")
	}

	// Unknown user still reports not found.
	if resp := get("qqnope"); resp.Error != "User not found" {
		t.Errorf("miss: error = %q, want %q", resp.Error, "User not found")
	}
}
