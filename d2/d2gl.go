package d2

import (
	"fmt"
	"io/ioutil"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/nokka/slashdiablo-launcher/storage"
)

// D2GL config profiles. D2GL parses "-config <name>" out of the game command
// line itself and then reads and writes d2gl_<name>.ini in the game directory,
// so giving the first box its own profile lets it run at a different resolution
// from the loaders without needing a second install. Both files stay under
// D2GL's control, which is what makes this safe: the in game options menu
// (ctrl+O) saves back to whichever profile that box was launched with.
const (
	d2glMainProfile   = "main"
	d2glLoaderProfile = "loader"
)

// d2glScreenSection is the ini section the managed keys live in.
const d2glScreenSection = "[Screen]"

// d2glProfileFor returns the config profile for the given instance of a game,
// or an empty string when the game shouldn't be launched with one.
func d2glProfileFor(game storage.Game, instance int) string {
	if !d2glEnabled(game) || !game.D2GLSplitProfiles {
		return ""
	}

	if instance == 0 {
		return d2glMainProfile
	}

	return d2glLoaderProfile
}

// launchFlags returns the command line flags for the given instance of a game.
func launchFlags(game storage.Game, instance int) []string {
	profile := d2glProfileFor(game, instance)
	if profile == "" {
		return game.Flags
	}

	// Copy rather than appending to game.Flags directly, whose backing array is
	// shared by every instance of this game.
	flags := make([]string, 0, len(game.Flags)+2)
	flags = append(flags, game.Flags...)

	return append(flags, "-config", profile)
}

// d2glProfilePath is the ini a box launched with the given profile reads. An
// empty profile is the shared d2gl.ini, which is what runs when profiles
// aren't split.
func d2glProfilePath(gamePath string, profile string) string {
	if profile == "" {
		return localizePath(fmt.Sprintf("%s/d2gl.ini", gamePath))
	}

	return localizePath(fmt.Sprintf("%s/d2gl_%s.ini", gamePath, profile))
}

// applyD2GLProfiles writes the launcher owned keys into every config the game
// will actually launch with, before any box starts. Everything else in the file
// is left alone, so D2GL's own comments and the settings players change with
// ctrl+O survive.
func applyD2GLProfiles(game storage.Game) error {
	if !d2glEnabled(game) {
		return nil
	}

	// Cursor lock is a personal preference rather than a per box one, so it
	// goes into every profile.
	shared := map[string]string{
		"unlock_cursor": strconv.FormatBool(game.D2GLUnlockCursor),
	}

	// Without split profiles every box shares d2gl.ini, so there is no per box
	// resolution to write.
	if !game.D2GLSplitProfiles {
		return writeD2GLKeys(d2glProfilePath(game.Location, ""), shared)
	}

	profiles := map[string]string{
		d2glMainProfile:   game.D2GLMainResolution,
		d2glLoaderProfile: game.D2GLLoaderResolution,
	}

	for profile, resolution := range profiles {
		values := make(map[string]string, len(shared)+3)
		for key, value := range shared {
			values[key] = value
		}

		if width, height, ok := parseResolution(resolution); ok {
			values["window_width"] = strconv.Itoa(width)
			values["window_height"] = strconv.Itoa(height)
			// A fullscreen window ignores the size entirely, so an explicit
			// resolution only means anything windowed.
			values["fullscreen"] = "false"
		}

		if err := writeD2GLKeys(d2glProfilePath(game.Location, profile), values); err != nil {
			return err
		}
	}

	return nil
}

// parseResolution splits a "1920x1080" style resolution. An unset or malformed
// value reports false so the caller leaves the profile alone.
func parseResolution(resolution string) (int, int, bool) {
	parts := strings.Split(strings.TrimSpace(resolution), "x")
	if len(parts) != 2 {
		return 0, 0, false
	}

	width, err := strconv.Atoi(strings.TrimSpace(parts[0]))
	if err != nil || width <= 0 {
		return 0, 0, false
	}

	height, err := strconv.Atoi(strings.TrimSpace(parts[1]))
	if err != nil || height <= 0 {
		return 0, 0, false
	}

	return width, height, true
}

// writeD2GLKeys sets the given keys on an existing profile, or creates a
// minimal one that D2GL will expand on first launch.
func writeD2GLKeys(path string, values map[string]string) error {
	contents, err := ioutil.ReadFile(path)
	if err != nil {
		if !os.IsNotExist(err) {
			return err
		}

		return ioutil.WriteFile(path, []byte(newD2GLProfile(values)), storage.Permissions)
	}

	return ioutil.WriteFile(path, []byte(updateD2GLProfile(string(contents), values)), storage.Permissions)
}

// newD2GLProfile is the smallest file D2GL will accept. It rewrites it in full,
// comments and all, the first time it loads it.
func newD2GLProfile(values map[string]string) string {
	var b strings.Builder

	b.WriteString(d2glScreenSection)
	b.WriteString("\n")

	for _, key := range sortedKeys(values) {
		fmt.Fprintf(&b, "%s=%s\n", key, values[key])
	}

	return b.String()
}

// updateD2GLProfile replaces the managed keys in place, leaving every other
// line, including D2GL's comments, exactly as it found them.
func updateD2GLProfile(contents string, values map[string]string) string {
	lines := strings.Split(contents, "\n")
	written := make(map[string]bool, len(values))
	screen := -1

	for i, line := range lines {
		trimmed := strings.TrimSpace(line)

		if strings.EqualFold(trimmed, d2glScreenSection) {
			screen = i
			continue
		}

		// Comments in this file start with ';', and a key without '=' is not
		// one of ours.
		separator := strings.Index(trimmed, "=")
		if strings.HasPrefix(trimmed, ";") || separator <= 0 {
			continue
		}

		key := strings.TrimSpace(trimmed[:separator])
		if value, ok := values[key]; ok && !written[key] {
			lines[i] = fmt.Sprintf("%s=%s", key, value)
			written[key] = true
		}
	}

	// Anything the file didn't already carry goes directly under [Screen], or
	// in a new section if the file somehow has none.
	var missing []string
	for _, key := range sortedKeys(values) {
		if !written[key] {
			missing = append(missing, fmt.Sprintf("%s=%s", key, values[key]))
		}
	}

	if len(missing) == 0 {
		return strings.Join(lines, "\n")
	}

	if screen == -1 {
		lines = append(lines, d2glScreenSection)
		screen = len(lines) - 1
	}

	rest := append([]string{}, lines[screen+1:]...)
	lines = append(lines[:screen+1], append(missing, rest...)...)

	return strings.Join(lines, "\n")
}

func sortedKeys(values map[string]string) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	return keys
}
