package d2

import (
	"fmt"
	"io/ioutil"
	"os"
	"strings"

	"github.com/nokka/slashdiablo-launcher/storage"
)

// maphackSettingsFile holds the maphack toggles. The patch marks it ignore_crc
// and its own header calls it a user owned template, so the launcher edits only
// the keys it manages and leaves every other line, comment, hotkey and bit of
// alignment exactly as it found it.
const maphackSettingsFile = "BH_settings.cfg"

// maphackComment is how BH_settings.cfg comments start. Note it is "//" rather
// than the ";" used by the d2gl ini.
const maphackComment = "//"

// ManagedMaphackSettings are the boolean toggles the launcher exposes, in the
// order they appear in the UI. Values in this file come in three shapes:
// "True", "True, None" and "True, VK_K". Only the boolean is ever replaced, so
// a key bound to a hotkey keeps it.
var ManagedMaphackSettings = []string{
	"Reveal Map",
	"Show Monsters",
	"Show Missiles",
	"Show Chests",
	"Infravision",
	"Remove Weather",
	"Display Level Names",
	"Advanced Item Display",
	"Show Ethereal",
	"Show Sockets",
	"Show iLvl",
	"Show Rune Numbers",
	"Experience Meter",
	"Stats on Right",
}

func maphackSettingsPath(gamePath string) string {
	return localizePath(fmt.Sprintf("%s/%s", gamePath, maphackSettingsFile))
}

// readMaphackSettings returns the current value of every managed toggle. A key
// the file doesn't carry reports false rather than failing, so a trimmed down
// or older settings file still opens.
func readMaphackSettings(gamePath string) (map[string]bool, error) {
	settings := make(map[string]bool, len(ManagedMaphackSettings))
	for _, key := range ManagedMaphackSettings {
		settings[key] = false
	}

	contents, err := ioutil.ReadFile(maphackSettingsPath(gamePath))
	if err != nil {
		// No maphack installed yet, report the defaults rather than an error.
		if os.IsNotExist(err) {
			return settings, nil
		}

		return nil, err
	}

	for _, line := range strings.Split(string(contents), "\n") {
		key, value, ok := splitMaphackLine(line)
		if !ok {
			continue
		}

		if _, managed := settings[key]; managed {
			settings[key] = parseMaphackBool(value)
		}
	}

	return settings, nil
}

// writeMaphackSettings updates the managed toggles in place.
func writeMaphackSettings(gamePath string, values map[string]bool) error {
	path := maphackSettingsPath(gamePath)

	contents, err := ioutil.ReadFile(path)
	if err != nil {
		if !os.IsNotExist(err) {
			return err
		}

		contents = []byte{}
	}

	lines := strings.Split(string(contents), "\n")
	written := make(map[string]bool, len(values))

	for i, line := range lines {
		key, _, ok := splitMaphackLine(line)
		if !ok {
			continue
		}

		value, managed := values[key]
		if !managed || written[key] {
			continue
		}

		lines[i] = setMaphackValue(line, value)
		written[key] = true
	}

	// Anything the file didn't carry gets appended, so a toggle the player set
	// in the launcher still takes effect on a trimmed down settings file.
	var missing []string
	for _, key := range ManagedMaphackSettings {
		value, managed := values[key]
		if managed && !written[key] {
			missing = append(missing, fmt.Sprintf("%s: %s", key, maphackBool(value)))
		}
	}

	if len(missing) > 0 {
		header := []string{"", maphackComment + " Added by the SlashDiablo launcher"}
		lines = append(lines, append(header, missing...)...)
	}

	return ioutil.WriteFile(path, []byte(strings.Join(lines, "\n")), storage.Permissions)
}

// splitMaphackLine pulls the key and value out of a "Key: Value" line, skipping
// comments and anything that isn't a setting.
func splitMaphackLine(line string) (string, string, bool) {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" || strings.HasPrefix(trimmed, maphackComment) {
		return "", "", false
	}

	// Only the first colon separates key from value; AutomapInfo lines carry
	// more of them inside the value.
	separator := strings.Index(trimmed, ":")
	if separator <= 0 {
		return "", "", false
	}

	return strings.TrimSpace(trimmed[:separator]), strings.TrimSpace(trimmed[separator+1:]), true
}

// parseMaphackBool reads the boolean out of "True", "True, None" or
// "True, VK_K // comment".
func parseMaphackBool(value string) bool {
	value = stripMaphackComment(value)

	if index := strings.Index(value, ","); index >= 0 {
		value = value[:index]
	}

	return strings.EqualFold(strings.TrimSpace(value), "true")
}

// setMaphackValue replaces just the boolean on a line, preserving the hotkey,
// any trailing comment and the whitespace the file lines its values up with.
func setMaphackValue(line string, value bool) string {
	separator := strings.Index(line, ":")
	if separator < 0 {
		return line
	}

	head := line[:separator+1]
	tail := line[separator+1:]

	// Hold the trailing comment aside so a hotkey-less value doesn't swallow it.
	var comment string
	if index := strings.Index(tail, maphackComment); index >= 0 {
		comment = tail[index:]
		tail = tail[:index]
	}

	// Keep the leading run of spaces so columns stay lined up.
	padding := tail[:len(tail)-len(strings.TrimLeft(tail, " \t"))]

	rest := ""
	if index := strings.Index(tail, ","); index >= 0 {
		rest = strings.TrimRight(tail[index:], " \t")
	}

	rebuilt := head + padding + maphackBool(value) + rest
	if comment != "" {
		rebuilt += " " + comment
	}

	return rebuilt
}

func maphackBool(value bool) string {
	if value {
		return "True"
	}

	return "False"
}

func stripMaphackComment(value string) string {
	if index := strings.Index(value, maphackComment); index >= 0 {
		return value[:index]
	}

	return value
}
