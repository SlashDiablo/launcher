package d2

import (
	"io/ioutil"
	"path/filepath"
	"strings"
	"testing"
)

func writeFixture(t *testing.T, dir string) {
	t.Helper()

	if err := ioutil.WriteFile(filepath.Join(dir, maphackSettingsFile), []byte(maphackFixture), 0644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}

// applyMaphackFixture writes the fixture to a temp dir, applies the values and
// returns the resulting file.
func applyMaphackFixture(t *testing.T, values map[string]bool) string {
	t.Helper()

	dir := t.TempDir()
	writeFixture(t, dir)

	if err := writeMaphackSettings(storedPath(dir), values); err != nil {
		t.Fatalf("writeMaphackSettings: %v", err)
	}

	contents, err := ioutil.ReadFile(filepath.Join(dir, maphackSettingsFile))
	if err != nil {
		t.Fatalf("read back: %v", err)
	}

	return string(contents)
}

func TestSplitMaphackLine(t *testing.T) {
	tests := []struct {
		line  string
		key   string
		value string
		ok    bool
	}{
		{"Reveal Map:             True, None", "Reveal Map", "True, None", true},
		{"Show Chests:          True, VK_K", "Show Chests", "True, VK_K", true},
		{"Show Difficulty:True", "Show Difficulty", "True", true},
		{"Skill Warning[16]:      True            // enchant", "Skill Warning[16]", "True            // enchant", true},
		// The value carries more colons than the separator.
		{"AutomapInfo[0]:         Name: %GAMENAME%", "AutomapInfo[0]", "Name: %GAMENAME%", true},
		{"// Reveal Map: True", "", "", false},
		{"//Maphack Configuration", "", "", false},
		{"", "", "", false},
		{"   ", "", "", false},
		{"no separator here", "", "", false},
	}

	for _, tt := range tests {
		key, value, ok := splitMaphackLine(tt.line)
		if ok != tt.ok || key != tt.key || value != tt.value {
			t.Errorf("splitMaphackLine(%q) = %q, %q, %v; want %q, %q, %v",
				tt.line, key, value, ok, tt.key, tt.value, tt.ok)
		}
	}
}

func TestParseMaphackBool(t *testing.T) {
	tests := []struct {
		value string
		want  bool
	}{
		{"True, None", true},
		{"True, VK_K", true},
		{"False, None", false},
		{"True", true},
		{"False", false},
		{"true", true},
		{"True            // enchant", true},
		{"False           // cyclone armor", false},
	}

	for _, tt := range tests {
		if got := parseMaphackBool(tt.value); got != tt.want {
			t.Errorf("parseMaphackBool(%q) = %v; want %v", tt.value, got, tt.want)
		}
	}
}

func TestSetMaphackValueKeepsHotkey(t *testing.T) {
	tests := []struct {
		line  string
		value bool
		want  string
	}{
		// The hotkey has to survive a toggle.
		{"Show Chests:          True, VK_K", false, "Show Chests:          False, VK_K"},
		{"Experience Meter:		True, VK_NUMPAD7", false, "Experience Meter:		False, VK_NUMPAD7"},
		// Alignment is preserved so the file keeps its columns.
		{"Reveal Map:             True, None", false, "Reveal Map:             False, None"},
		{"Reveal Map:             False, None", true, "Reveal Map:             True, None"},
		// No hotkey at all.
		{"Show Difficulty:True", false, "Show Difficulty:False"},
		// Trailing comment must not be swallowed.
		{"Skill Warning[16]:      True            // enchant", false, "Skill Warning[16]:      False // enchant"},
	}

	for _, tt := range tests {
		if got := setMaphackValue(tt.line, tt.value); got != tt.want {
			t.Errorf("setMaphackValue(%q, %v)\n got: %q\nwant: %q", tt.line, tt.value, got, tt.want)
		}
	}
}

// The real settings file shape, trimmed to the interesting lines.
const maphackFixture = `// Slash Diablo Default BH_settings, v1.4
// This file will be customized by the user.

Monster Color[Normal]:   0x5B

//Maphack Configuration
Reveal Map:             True, None
Show Monsters:          True, None
Show Missiles:          False, None
Show Chests:            True, VK_K
Infravision:            True, None

Skill Warning[16]:      True            // enchant

//Item Configuration
Show Ethereal:          True, None
Advanced Item Display:  True, None

Filter Level: 0
`

func TestWriteMaphackSettingsPreservesFile(t *testing.T) {
	updated := applyMaphackFixture(t, map[string]bool{
		"Show Missiles": true,
		"Reveal Map":    false,
		"Show Chests":   false,
	})

	for _, want := range []string{
		"Show Missiles:          True, None",
		"Reveal Map:             False, None",
		// Hotkey survives.
		"Show Chests:            False, VK_K",
	} {
		if !strings.Contains(updated, want) {
			t.Errorf("missing %q in:\n%s", want, updated)
		}
	}

	// Untouched settings, comments, colours and unrelated keys all survive.
	for _, want := range []string{
		"// Slash Diablo Default BH_settings, v1.4",
		"// This file will be customized by the user.",
		"Monster Color[Normal]:   0x5B",
		"//Maphack Configuration",
		"Show Monsters:          True, None",
		"Infravision:            True, None",
		"Skill Warning[16]:      True            // enchant",
		"Filter Level: 0",
	} {
		if !strings.Contains(updated, want) {
			t.Errorf("clobbered %q in:\n%s", want, updated)
		}
	}
}

// A key the launcher manages but the file does not carry has to be appended,
// otherwise toggling it in the UI would silently do nothing.
func TestWriteMaphackSettingsAppendsMissing(t *testing.T) {
	updated := applyMaphackFixture(t, map[string]bool{"Stats on Right": true})

	if !strings.Contains(updated, "Stats on Right: True") {
		t.Errorf("missing key not appended:\n%s", updated)
	}

	if !strings.Contains(updated, "// Added by the SlashDiablo launcher") {
		t.Errorf("appended block not marked:\n%s", updated)
	}

	// Appending must not disturb what was already there.
	if !strings.Contains(updated, "Reveal Map:             True, None") {
		t.Errorf("existing settings changed:\n%s", updated)
	}
}

func TestReadMaphackSettings(t *testing.T) {
	dir := t.TempDir()
	writeFixture(t, dir)

	settings, err := readMaphackSettings(storedPath(dir))
	if err != nil {
		t.Fatalf("readMaphackSettings: %v", err)
	}

	for key, want := range map[string]bool{
		"Reveal Map":            true,
		"Show Missiles":         false,
		"Show Chests":           true,
		"Advanced Item Display": true,
		// Present in the managed list but absent from the file.
		"Stats on Right": false,
	} {
		if settings[key] != want {
			t.Errorf("%q = %v; want %v", key, settings[key], want)
		}
	}

	// Every managed key must be reported so the view has a value for each.
	for _, key := range ManagedMaphackSettings {
		if _, ok := settings[key]; !ok {
			t.Errorf("managed key %q missing from result", key)
		}
	}
}

// A missing settings file means maphack isn't installed yet, which should read
// as defaults rather than an error.
func TestReadMaphackSettingsMissingFile(t *testing.T) {
	settings, err := readMaphackSettings(storedPath(t.TempDir()))
	if err != nil {
		t.Fatalf("readMaphackSettings on missing file: %v", err)
	}

	if len(settings) != len(ManagedMaphackSettings) {
		t.Errorf("got %d settings, want %d", len(settings), len(ManagedMaphackSettings))
	}
}
