# Local test environment

Runs the launcher against a local file server instead of `slashdiablo.net`, so
patching and mod installs can be exercised without touching production.

There are two environments. **Windows is the one that matters** — it is the
release target, and the D2 specific code only exists there. The WSL/Linux build
is a faster loop for QML and ordinary Go work.

| | Windows | WSL / Linux |
| --- | --- | --- |
| script | `testenv\win-dev.ps1` | `testenv/dev.sh` |
| mod install detection | yes | **no**, stubbed |
| game version detection | yes | **no**, stubbed |
| launching Diablo II | yes | **no**, stubbed |
| registry / DEP fixes | yes | **no**, stubbed |
| incremental Go rebuild | ~6s | ~7s |

The Linux stubs live in `d2/diablo_linux.go`; `isModInstalled` and
`validate113cVersion` unconditionally return `false`, so on Linux the launcher
re-downloads mods every time and never recognises a 1.13c install.

## How it works

The launcher reads two addresses from the environment (see `main.go`):

| Variable | Default | Purpose |
| --- | --- | --- |
| `SLASHDIABLO_FILES_ADDRESS` | `http://slashdiablo.net/files` | news, available mods, patch files |
| `SLASHDIABLO_LADDER_ADDRESS` | `https://ladder.slashdiablo.net` | ladder rankings |

`make_fixtures.py` builds a directory tree matching the layout the launcher
expects, and `serve.py` serves it.

> **Only put a mod under `testenv/files` if you are developing it.** Anything
> there is served in preference to production, and the launcher will happily
> download it over a real install — a stub `BH.dll` will replace a working
> maphack with a 26 byte text file. `make_fixtures.py` therefore creates only
> the d2gl directory and takes the hd/maphack version lists from production so
> those proxy through untouched. Test against a copy of a game directory.

`serve.py` serves anything present under `testenv/files` from disk and proxies
everything else to `slashdiablo.net`. So a mod under development is served
locally while the `1.13c` and SlashDiablo patch manifests still come from
production, which is what makes a full patch run work end to end. Each request
is logged as `[local]` or `[proxy]` so it is obvious which is which. Pass
`--no-proxy` to 404 instead of falling back.

## Fixtures

Passing a real [D2GL release zip](https://github.com/bayaraa/d2gl/releases)
unpacks the actual binaries; without it you get small stub files.

```bash
curl -L -o /tmp/d2gl.zip \
  https://github.com/bayaraa/d2gl/releases/download/v1.3.3/D2GL.v1.3.3.zip
python3 testenv/make_fixtures.py --d2gl-zip /tmp/d2gl.zip
```

This creates `testenv/files/` (served over HTTP) and `testenv/d2/` (a stand-in
Diablo II directory). Both are gitignored; `make_fixtures.py` is not.

Each mod directory needs a `manifest.json` listing every file with a CRC32
(standard IEEE polynomial, matching `d2/crc.go`). Re-run `make_fixtures.py`
after changing any file in a mod directory so the CRCs and sizes stay in sync —
the launcher compares them to decide what to download.

## Running

```bash
# terminal 1
./testenv/dev.sh serve
# terminal 2
./testenv/dev.sh run
```

```powershell
# terminal 1
.\testenv\win-dev.ps1 serve
# terminal 2
.\testenv\win-dev.ps1 run
```

QML is loaded from disk in development mode, so UI changes need a restart but no
rebuild. Only Go changes require `build`.

On Windows the exe is built to `deploy\windows\` and `windeployqt` copies the Qt
DLLs beside it, so it runs from Explorer as well as from the script. Without
that step it only starts from a shell with `C:\Qt\5.15.2\mingw81_64\bin` on
`PATH`, and otherwise fails with *"The code execution cannot proceed because
Qt5Network.dll was not found"*. Re-run the copy with `win-dev.ps1 deploy`.

> The launcher reads and **writes** `%LOCALAPPDATA%\slashdiablo.net\SlashDiablo
> launcher\config.json`, shared with any installed release build. Point the dev
> build at a copy of your Diablo II directory before exercising mod installs.

## Releasing

```powershell
.\testenv\win-dev.ps1 release
```

That runs `dist` (QML compiled in, symbols stripped, console detached) and then
packages `deploy\windows\` with Inno Setup, producing
`installer\output\SlashDiablo_Installer_<version>.exe`. Either half can be run
on its own as `dist` or `installer`.

Inno Setup is needed once: `winget install JRSoftware.InnoSetup`. winget puts it
under `%LOCALAPPDATA%\Programs` and does not add it to `PATH`, so `iscc` will not
resolve on its own — the script finds it.

The version is not written anywhere in the installer script. It is read out of
the built exe, which `go generate` populates from `versioninfo.json`, so bumping
the version there is enough. Bump `BUILD_VERSION` and `SetApplicationVersion` in
`main.go` to match, then re-run `go generate`.

`installer\windows\slashdiablo-launcher.iss` packages the deploy directory with a
wildcard rather than a file list. The Advanced Installer project it replaces
(removed in `1266eb6`) enumerated every file and referenced a build directory
outside the repo, so it broke whenever the Qt dependencies changed. Keep the
wildcard.

## First time setup

### Windows

Needs Go 1.18 (newer versions have not been tried with therecipe/qt), Qt 5.15.2
for MinGW, and the MinGW toolchain.

```powershell
# Go 1.18 -> C:\go1.18 (extract the zip from https://go.dev/dl/)
# Qt + compiler, via aqtinstall
python -m pip install --user aqtinstall
python -m aqt install-tool windows desktop tools_mingw qt.tools.win64_mingw810 -O C:\Qt
python -m aqt install-qt   windows desktop 5.15.2 win64_mingw81 -m qtscript -O C:\Qt

# GOPATH deps, then junction this repo into GOPATH
git clone --depth 1 https://github.com/therecipe/qt.git      $env:USERPROFILE\go\src\github.com\therecipe\qt
git clone --depth 1 -b v1.9.3  https://github.com/sirupsen/logrus.git $env:USERPROFILE\go\src\github.com\sirupsen\logrus
git clone --depth 1 -b v0.1.12 https://github.com/golang/tools.git    $env:USERPROFILE\go\src\golang.org\x\tools
git clone --depth 1 -b v0.13.0 https://github.com/golang/sys.git      $env:USERPROFILE\go\src\golang.org\x\sys
git clone --depth 1 -b v0.12.0 https://github.com/golang/mod.git      $env:USERPROFILE\go\src\golang.org\x\mod
git clone --depth 1 -b v1.6.0  https://github.com/google/uuid.git     $env:USERPROFILE\go\src\github.com\google\uuid
git clone --depth 1 https://github.com/nokka/goqmlframeless.git       $env:USERPROFILE\go\src\github.com\nokka\goqmlframeless
New-Item -ItemType Junction -Path $env:USERPROFILE\go\src\github.com\nokka\slashdiablo-launcher -Target <this repo>

.\testenv\win-dev.ps1 tools
.\testenv\win-dev.ps1 check    # confirm Qt is found before the slow step
.\testenv\win-dev.ps1 setup    # generates bindings, ~5 min
.\testenv\win-dev.ps1 build    # first build ~20 min, then ~6s
```

Three things about therecipe/qt on Windows, all handled by `win-dev.ps1` but
worth knowing since none of them fail loudly:

1. It hardcodes `mingw73_64` and `Tools\mingw730_64` paths with no environment
   override. Qt 5.15.2 only ships `mingw81_64`, so directory junctions are
   needed:
   ```powershell
   New-Item -ItemType Junction -Path C:\Qt\5.15.2\mingw73_64  -Target C:\Qt\5.15.2\mingw81_64
   New-Item -ItemType Junction -Path C:\Qt\Tools\mingw730_64 -Target C:\Qt\Tools\mingw810_64
   ```
2. `aqtinstall` does not create `bin\qtenv2.bat`, which therecipe tries to load.
   A minimal one setting `PATH` is enough.
3. **`QT_API=5.13.0` is required.** therecipe generates bindings by parsing Qt
   `.index` doc files, ships bundles only up to 5.13.0, and its fallback to the
   installed docs is Linux only. Without it every module parses as EOF and
   generates an *empty* binding — while still exiting 0 and reporting "40
   modules generated". The tell is `core.go` being ~800 bytes instead of ~2 MB,
   and generation finishing in one minute instead of five.

### WSL / Linux

```bash
sudo apt install -y build-essential pkg-config libgl1-mesa-dev \
  qtbase5-dev qtdeclarative5-dev qtquickcontrols2-5-dev qttools5-dev libqt5svg5-dev \
  qtmultimedia5-dev qtscript5-dev libqt5remoteobjects5-dev \
  qml-module-qtquick2 qml-module-qtquick-controls qml-module-qtquick-controls2 \
  qml-module-qtquick-dialogs qml-module-qtquick-layouts qml-module-qtquick-window2 \
  qml-module-qtqml-models2 qml-module-qtgraphicaleffects
```

Install Go 1.18 to `~/sdk/go1.18`, clone the same dependencies into `~/go/src`,
symlink this repo to `~/go/src/github.com/nokka/slashdiablo-launcher`, then run
`qtsetup`.

`qtmultimedia5-dev`, `qtscript5-dev` and `libqt5remoteobjects5-dev` must be
installed *before* `qtsetup` runs. therecipe emits one shared include block
referencing every Qt module it knows, and bakes the include and link flags into
its cgo files at generation time. Installing them afterwards means editing
`CGO_CXXFLAGS`/`CGO_LDFLAGS` by hand, which is what `dev.sh` currently does.

WSLg reports 96 DPI regardless of the Windows display scaling, so the window
comes out physically small on a high DPI monitor. `dev.sh` sets
`QT_SCALE_FACTOR=1.5` to compensate.

## Known issue: duplicate icon resources

The repo commits both `icon_windows.syso` and `resource.syso`, and Go links every
`.syso` in the package directory. On Windows the linker warns:

```
ld.exe: .rsrc merge failure: duplicate leaf: type: 3 (ICON) name: 3 lang: 409
```

The build still succeeds. `resource.syso` is the one `go generate` produces (see
the `//go:generate` line in `main.go`); `icon_windows.syso` appears to predate it.
