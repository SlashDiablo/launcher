package d2

import (
	"io/ioutil"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/nokka/slashdiablo-launcher/storage"
)

func TestParseResolution(t *testing.T) {
	tests := []struct {
		resolution string
		width      int
		height     int
		ok         bool
	}{
		{"3200x1800", 3200, 1800, true},
		{"800x600", 800, 600, true},
		{"default", 0, 0, false},
		{"", 0, 0, false},
		{"1920", 0, 0, false},
		{"axb", 0, 0, false},
		{"0x600", 0, 0, false},
	}

	for _, tt := range tests {
		width, height, ok := parseResolution(tt.resolution)
		if ok != tt.ok || width != tt.width || height != tt.height {
			t.Errorf("parseResolution(%q) = %d, %d, %v; want %d, %d, %v",
				tt.resolution, width, height, ok, tt.width, tt.height, tt.ok)
		}
	}
}

func TestLaunchFlags(t *testing.T) {
	base := []string{"-3dfx", "-skiptobnet"}

	game := storage.Game{
		Flags:             base,
		D2GLVersion:       "1.3.3",
		D2GLSplitProfiles: true,
	}

	first := launchFlags(game, 0)
	if got := strings.Join(first, " "); got != "-3dfx -skiptobnet -config main" {
		t.Errorf("instance 0 flags = %q", got)
	}

	second := launchFlags(game, 1)
	if got := strings.Join(second, " "); got != "-3dfx -skiptobnet -config loader" {
		t.Errorf("instance 1 flags = %q", got)
	}

	// The first instance's flags must not have been clobbered by the second,
	// which is what happens if the slices share a backing array.
	if got := strings.Join(first, " "); got != "-3dfx -skiptobnet -config main" {
		t.Errorf("instance 0 flags after second launch = %q", got)
	}

	if got := strings.Join(base, " "); got != "-3dfx -skiptobnet" {
		t.Errorf("game flags were mutated: %q", got)
	}
}

func TestLaunchFlagsWithoutSplit(t *testing.T) {
	// d2gl selected but profiles not split.
	game := storage.Game{Flags: []string{"-3dfx"}, D2GLVersion: "1.3.3"}
	if got := strings.Join(launchFlags(game, 1), " "); got != "-3dfx" {
		t.Errorf("unsplit flags = %q", got)
	}

	// Split asked for, but d2gl isn't installed on this game.
	game = storage.Game{Flags: []string{"-3dfx"}, D2GLVersion: "none", D2GLSplitProfiles: true}
	if got := strings.Join(launchFlags(game, 1), " "); got != "-3dfx" {
		t.Errorf("flags without d2gl = %q", got)
	}
}

func TestUpdateD2GLProfilePreservesFile(t *testing.T) {
	existing := `; ==== D2GL Configs ====

[Screen]

; Game will run in fullscreen window.
fullscreen=true

; Window size.
window_width=1024
window_height=768

; Vertical synchronization.
vsync=true
`

	got := updateD2GLProfile(existing, map[string]string{
		"window_width":  "3200",
		"window_height": "1800",
		"fullscreen":    "false",
	})

	for _, want := range []string{"window_width=3200", "window_height=1800", "fullscreen=false"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}

	// Everything the launcher does not manage has to survive untouched.
	for _, want := range []string{"; ==== D2GL Configs ====", "; Window size.", "vsync=true"} {
		if !strings.Contains(got, want) {
			t.Errorf("clobbered %q in:\n%s", want, got)
		}
	}

	if strings.Contains(got, "window_width=1024") || strings.Contains(got, "fullscreen=true") {
		t.Errorf("old values left behind in:\n%s", got)
	}
}

func TestApplyD2GLProfilesWritesCursorToBothProfiles(t *testing.T) {
	dir := t.TempDir()

	game := storage.Game{
		Location:             storedPath(dir),
		D2GLVersion:          "1.3.3",
		D2GLSplitProfiles:    true,
		D2GLMainResolution:   "3200x1800",
		D2GLLoaderResolution: "800x600",
		D2GLUnlockCursor:     true,
	}

	if err := applyD2GLProfiles(game); err != nil {
		t.Fatalf("applyD2GLProfiles: %v", err)
	}

	main := readFile(t, filepath.Join(dir, "d2gl_main.ini"))
	loader := readFile(t, filepath.Join(dir, "d2gl_loader.ini"))

	// Cursor is a personal preference, so it lands in both.
	for name, contents := range map[string]string{"main": main, "loader": loader} {
		if !strings.Contains(contents, "unlock_cursor=true") {
			t.Errorf("%s profile missing cursor setting:\n%s", name, contents)
		}
	}

	// Resolution is per box.
	if !strings.Contains(main, "window_width=3200") {
		t.Errorf("main resolution wrong:\n%s", main)
	}
	if !strings.Contains(loader, "window_width=800") {
		t.Errorf("loader resolution wrong:\n%s", loader)
	}
}

// Without split profiles every box shares d2gl.ini, and the cursor setting
// still has to reach it.
func TestApplyD2GLProfilesUnsplitWritesSharedIni(t *testing.T) {
	dir := t.TempDir()

	game := storage.Game{
		Location:         storedPath(dir),
		D2GLVersion:      "1.3.3",
		D2GLUnlockCursor: true,
	}

	if err := applyD2GLProfiles(game); err != nil {
		t.Fatalf("applyD2GLProfiles: %v", err)
	}

	shared := readFile(t, filepath.Join(dir, "d2gl.ini"))
	if !strings.Contains(shared, "unlock_cursor=true") {
		t.Errorf("shared ini missing cursor setting:\n%s", shared)
	}

	// No profiles should have been created.
	if _, err := os.Stat(filepath.Join(dir, "d2gl_main.ini")); !os.IsNotExist(err) {
		t.Error("main profile created despite profiles not being split")
	}
}

// d2gl not selected at all means the launcher writes nothing.
func TestApplyD2GLProfilesWithoutD2GL(t *testing.T) {
	dir := t.TempDir()

	if err := applyD2GLProfiles(storage.Game{Location: storedPath(dir), D2GLVersion: "none", D2GLUnlockCursor: true}); err != nil {
		t.Fatalf("applyD2GLProfiles: %v", err)
	}

	files, _ := ioutil.ReadDir(dir)
	if len(files) != 0 {
		t.Errorf("wrote %d files for a game without d2gl", len(files))
	}
}

// storedPath turns a real directory into the form the launcher keeps game
// locations in. The QML file dialog hands paths over as "/C:/Games/Diablo II",
// and localizePath on Windows strips that leading slash back off.
func storedPath(dir string) string {
	if runtime.GOOS == "windows" {
		return "/" + filepath.ToSlash(dir)
	}

	return dir
}

func readFile(t *testing.T, path string) string {
	t.Helper()

	contents, err := ioutil.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}

	return string(contents)
}

func TestUpdateD2GLProfileInsertsMissingKeys(t *testing.T) {
	existing := "[Screen]\nvsync=true\n"

	got := updateD2GLProfile(existing, map[string]string{
		"window_width":  "800",
		"window_height": "600",
	})

	if !strings.Contains(got, "window_width=800") || !strings.Contains(got, "window_height=600") {
		t.Errorf("keys not inserted:\n%s", got)
	}

	// They have to land inside [Screen], not after an unrelated section.
	screen := strings.Index(got, "[Screen]")
	width := strings.Index(got, "window_width=800")
	if screen == -1 || width < screen {
		t.Errorf("keys inserted outside [Screen]:\n%s", got)
	}

	if !strings.Contains(got, "vsync=true") {
		t.Errorf("existing key lost:\n%s", got)
	}
}

func TestUpdateD2GLProfileIgnoresComments(t *testing.T) {
	// A commented out key must not be treated as the real one.
	existing := "[Screen]\n; window_width=1024\nwindow_width=1280\n"

	got := updateD2GLProfile(existing, map[string]string{"window_width": "1920"})

	if !strings.Contains(got, "; window_width=1024") {
		t.Errorf("comment was rewritten:\n%s", got)
	}

	if !strings.Contains(got, "window_width=1920") {
		t.Errorf("real key not updated:\n%s", got)
	}
}

func TestNewD2GLProfile(t *testing.T) {
	got := newD2GLProfile(map[string]string{
		"window_width":  "1920",
		"window_height": "1080",
		"fullscreen":    "false",
	})

	if !strings.HasPrefix(got, "[Screen]\n") {
		t.Errorf("profile does not open with the section:\n%s", got)
	}

	for _, want := range []string{"fullscreen=false", "window_height=1080", "window_width=1920"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
}
