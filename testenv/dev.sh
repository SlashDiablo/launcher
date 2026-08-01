#!/usr/bin/env bash
# Build and run the launcher against the local fixture server.
#
#   ./testenv/dev.sh build    compile only
#   ./testenv/dev.sh run      compile and run
#   ./testenv/dev.sh serve    serve testenv/files on :8666
#
# QML is loaded from disk in development mode, so UI changes need a restart
# but no rebuild.

set -euo pipefail

REPO=github.com/nokka/slashdiablo-launcher
QT_INC=/usr/include/x86_64-linux-gnu/qt5
QT_LIB=/usr/lib/x86_64-linux-gnu
PORT=8666

export GOPATH="$HOME/go"
export PATH="$HOME/sdk/go1.18/bin:$GOPATH/bin:$PATH"
export GO111MODULE=off
export QT_PKG_CONFIG=true

# therecipe/qt generated its cgo flags before qtmultimedia5-dev, qtscript5-dev
# and libqt5remoteobjects5-dev were installed, so core.cpp references headers
# and symbols that its own flags do not cover. Fill in the gaps here rather
# than regenerating the bindings.
export CGO_CXXFLAGS="-I$QT_INC/QtMultimedia -I$QT_INC/QtScript -I$QT_INC/QtRemoteObjects"
export CGO_LDFLAGS="$QT_LIB/libQt5Multimedia.so $QT_LIB/libQt5Script.so $QT_LIB/libQt5RemoteObjects.so"

SRC="$GOPATH/src/$REPO"
BIN="$SRC/slashdiablo-launcher"

build() {
    # Regenerates the moc bindings for any changed QObject struct tags, then
    # compiles. Skip qtmoc with SKIP_MOC=1 when only ordinary Go code changed.
    if [ "${SKIP_MOC:-0}" != "1" ]; then
        qtmoc desktop "$REPO"
    fi
    go build -o "$BIN" "$SRC"
    echo "built $BIN"
}

run() {
    build
    cd "$SRC"
    # WSLg reports 96 DPI regardless of the Windows display scaling, so the
    # window comes out physically tiny on a high DPI monitor. Native Windows
    # builds read the real DPI and do not need this.
    ENVIRONMENT=development \
    DEBUG_MODE=true \
    QT_SCALE_FACTOR="${QT_SCALE_FACTOR:-1.5}" \
    SLASHDIABLO_FILES_ADDRESS="http://localhost:$PORT" \
        "$BIN"
}

serve() {
    if [ ! -d "$SRC/testenv/files" ]; then
        echo "no fixtures yet; run: python3 testenv/make_fixtures.py" >&2
        exit 1
    fi
    python3 "$SRC/testenv/serve.py" --port "$PORT"
}

case "${1:-run}" in
    build) build ;;
    run)   run ;;
    serve) serve ;;
    *)     echo "usage: $0 {build|run|serve}" >&2; exit 1 ;;
esac
