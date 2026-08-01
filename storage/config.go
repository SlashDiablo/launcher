package storage

// DefaultLaunchDelay is used if a launch delay hasn't been set by a user.
const DefaultLaunchDelay = 1000

// Config is the configuration required to run the app.
type Config struct {
	Games       []Game `json:"games"`
	LaunchDelay int    `json:"launch_delay"`
}

// Game represents a game setup by the user.
type Game struct {
	ID             string   `json:"id"`
	Location       string   `json:"location"`
	Instances      int      `json:"instances"`
	OverrideBHCfg  bool     `json:"override_bh_cfg"`
	Flags          []string `json:"flags"`
	HDVersion      string   `json:"hd_version"`
	MaphackVersion string   `json:"maphack_version"`
	D2GLVersion    string   `json:"d2gl_version"`

	// D2GLSplitProfiles launches the first instance with its own d2gl config,
	// so a main box can run at a different resolution than the loaders.
	D2GLSplitProfiles    bool   `json:"d2gl_split_profiles"`
	D2GLMainResolution   string `json:"d2gl_main_resolution"`
	D2GLLoaderResolution string `json:"d2gl_loader_resolution"`
}
