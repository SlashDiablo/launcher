package d2

import (
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
