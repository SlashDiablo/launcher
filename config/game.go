package config

import (
	"github.com/therecipe/qt/core"
)

const (
	// ModVersionNone is used to determine that no mod version has been chosen for a game.
	ModVersionNone = "none"
)

// Game represents a diablo installation in the configuration.
type Game struct {
	core.QObject

	ID             string   `json:"id"`
	Location       string   `json:"location"`
	Instances      int      `json:"instances"`
	OverrideBHCfg  bool     `json:"override_bh_cfg"`
	Flags          []string `json:"flags"`
	HDVersion      string   `json:"hd_version"`
	MaphackVersion string   `json:"maphack_version"`
	D2GLVersion    string   `json:"d2gl_version"`

	D2GLSplitProfiles    bool   `json:"d2gl_split_profiles"`
	D2GLMainResolution   string `json:"d2gl_main_resolution"`
	D2GLLoaderResolution string `json:"d2gl_loader_resolution"`
}

// GameMods represents the mods available for a Diablo II game.
type GameMods struct {
	HD      []string `json:"hd"`
	Maphack []string `json:"maphack"`
	D2GL    []string `json:"d2gl"`
}
