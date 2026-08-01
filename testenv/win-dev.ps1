# Windows dev environment for the SlashDiablo launcher.
#
#   .\testenv\win-dev.ps1 tools      build the therecipe/qt command line tools
#   .\testenv\win-dev.ps1 check      show how therecipe resolves Qt and the compiler
#   .\testenv\win-dev.ps1 setup      generate the Qt bindings (slow, one time)
#   .\testenv\win-dev.ps1 build      qtmoc + go build
#   .\testenv\win-dev.ps1 deploy     copy the Qt DLLs next to the exe
#   .\testenv\win-dev.ps1 dist       standalone build with QML compiled in
#   .\testenv\win-dev.ps1 installer  package the last dist with Inno Setup
#   .\testenv\win-dev.ps1 release    dist + installer
#   .\testenv\win-dev.ps1 run        build then run against the local fixtures
#   .\testenv\win-dev.ps1 serve      serve testenv/files on :8666
#
# QML is loaded from disk in development mode, so UI changes need a restart
# but no rebuild.

param([string]$Task = "run")

$ErrorActionPreference = "Stop"

$Repo     = "github.com/nokka/slashdiablo-launcher"
$GoRoot   = "C:\go1.18"
$QtDir    = "C:\Qt"
$QtVer    = "5.15.2"
$QtSpec   = "mingw81_64"
$MinGW    = "$QtDir\Tools\mingw810_64"
$Port     = 8666

$env:GOROOT      = $GoRoot
$env:GOPATH      = "$env:USERPROFILE\go"
$env:GO111MODULE = "off"
$env:QT_DIR      = $QtDir
$env:QT_VERSION  = $QtVer
# therecipe generates bindings by parsing Qt .index doc files. It ships bundles
# only up to 5.13.0, and its fallback to the installed Qt docs is Linux only.
# Without this every module parses as EOF and generates an empty binding, which
# still exits 0 and looks like success. 5.13 is source compatible with 5.15.
$env:QT_API      = "5.13.0"
# Generating on Windows for Windows, therecipe turns its debug console on unless
# this is explicitly "false" (internal/cmd/setup/generate.go). That bakes
# -Wl,-subsystem,console into the cgo flags, which the external linker honours
# over go build's -H windowsgui, so the launcher opens a terminal behind itself.
# Changing this only takes effect after re-running setup.
$env:QT_DEBUG_CONSOLE = "false"
$env:PATH        = "$GoRoot\bin;$env:GOPATH\bin;$MinGW\bin;$QtDir\$QtVer\$QtSpec\bin;$env:PATH"

$Src = "$env:GOPATH\src\$($Repo -replace '/','\')"
# Built into deploy\, which is gitignored, so the Qt DLLs windeployqt copies
# alongside the exe do not litter the repo root.
$Out = "$Src\deploy\windows"
$Bin = "$Out\slashdiablo-launcher.exe"

function Invoke-Tools {
    Push-Location "$env:GOPATH\src\github.com\therecipe\qt"
    try {
        foreach ($c in "qtsetup", "qtdeploy", "qtmoc", "qtrcc", "qtminimal") {
            go build -tags=no_env -o "$env:GOPATH\bin\$c.exe" ".\cmd\$c"
            if ($LASTEXITCODE -ne 0) { throw "failed to build $c" }
            Write-Host "built $c"
        }
    } finally { Pop-Location }
}

function Invoke-Check {
    # Reports how therecipe resolves Qt, the compiler and the Go toolchain.
    # Worth running before Invoke-Setup, which is slow to fail.
    qtsetup check desktop
}

function Invoke-Setup {
    # Generates the Go/C++ bindings against the installed Qt. Takes a while and
    # only needs to be redone if the Qt installation changes.
    #
    # Only the generate step runs. Plain "qtsetup" would go on to compile all
    # ~40 Qt modules, but this app imports four (core, gui, quick, widgets) and
    # go build compiles those on demand.
    qtsetup generate desktop
}

function Invoke-Build {
    # qtmoc regenerates the bindings for changed QObject struct tags. Skip it
    # with -Env SKIP_MOC when only ordinary Go code changed.
    if ($env:SKIP_MOC -ne "1") { qtmoc desktop $Repo }
    New-Item -ItemType Directory -Force -Path $Out | Out-Null
    go build -o $Bin $Src
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
    Write-Host "built $Bin"
    # The exe links Qt dynamically, so without the DLLs beside it it only runs
    # from a shell that has Qt on PATH. Copy them so it is double clickable.
    if (-not (Test-Path "$Out\Qt5Network.dll")) { Invoke-Deploy }
}

function Invoke-Deploy {
    windeployqt --qmldir "$Src\qml" $Bin
    if ($LASTEXITCODE -ne 0) { throw "windeployqt failed" }
    Write-Host "deployed Qt runtime to $Out"
}

function Invoke-Dist {
    # Production style build: qtrcc compiles qml/ into a Qt resource so the exe
    # reads "qrc:/qml/main.qml" and no longer depends on the working directory.
    # Needed for a standalone exe; QML changes then require a rebuild, which is
    # why the development path loads QML from disk instead.
    qtrcc desktop $Repo
    if ($LASTEXITCODE -ne 0) { throw "qtrcc failed" }
    New-Item -ItemType Directory -Force -Path $Out | Out-Null
    # -s -w drops the debug symbols, which are most of the binary. -H windowsgui
    # detaches the console, otherwise the launcher opens a terminal behind it.
    go build -ldflags "-s -w -H windowsgui" -o $Bin $Src
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
    Invoke-Deploy
    Write-Host "standalone build at $Bin"
}

function Get-Iscc {
    # winget installs Inno Setup per user and does not add it to PATH, so look
    # in the usual places before giving up.
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $onPath = Get-Command iscc -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    throw "Inno Setup not found; install it with: winget install JRSoftware.InnoSetup"
}

function Invoke-Installer {
    if (-not (Test-Path $Bin)) { throw "no build to package; run: win-dev.ps1 dist" }
    $iscc = Get-Iscc
    & $iscc "$Src\installer\windows\slashdiablo-launcher.iss"
    if ($LASTEXITCODE -ne 0) { throw "iscc failed" }
}

function Invoke-Release {
    Invoke-Dist
    Invoke-Installer
}

function Invoke-Run {
    Invoke-Build
    # Run from the repo root so the development mode "qml/main.qml" path
    # resolves; only production builds read QML from the compiled resource.
    Push-Location $Src
    try {
        $env:ENVIRONMENT = "development"
        $env:DEBUG_MODE  = "true"
        $env:SLASHDIABLO_FILES_ADDRESS = "http://localhost:$Port"
        & $Bin
    } finally { Pop-Location }
}

function Invoke-Serve {
    if (-not (Test-Path "$Src\testenv\files")) {
        throw "no fixtures yet; run: python testenv\make_fixtures.py"
    }
    python "$Src\testenv\serve.py" --port $Port
}

switch ($Task) {
    "tools"     { Invoke-Tools }
    "check"     { Invoke-Check }
    "setup"     { Invoke-Setup }
    "build"     { Invoke-Build }
    "deploy"    { Invoke-Deploy }
    "dist"      { Invoke-Dist }
    "installer" { Invoke-Installer }
    "release"   { Invoke-Release }
    "run"       { Invoke-Run }
    "serve"     { Invoke-Serve }
    default  { throw "usage: win-dev.ps1 {tools|check|setup|build|deploy|dist|installer|release|run|serve}" }
}
