#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/macshot.xcodeproj"
SCHEME="macshot"
APP_NAME="ScreenShot"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
DMG_OUTPUT="$HOME/Desktop/${APP_NAME}.dmg"

# Find the DerivedData build dir (handles hash suffix)
find_app() {
    local build_dir
    build_dir=$(find "$DERIVED_DATA" -maxdepth 1 -name "macshot-*" -type d | head -1)
    if [[ -z "$build_dir" ]]; then
        echo "Error: Build directory not found. Run build first."
        exit 1
    fi
    echo "$build_dir/Build/Products/Release/${APP_NAME}.app"
}

# Release build
build() {
    echo "==> Building ${APP_NAME} (Release)..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release build 2>&1 | tail -3
    echo ""
}

# A: Install to /Applications
deploy_app() {
    build

    local app_path
    app_path=$(find_app)
    if [[ ! -d "$app_path" ]]; then
        echo "Error: ${APP_NAME}.app not found at $app_path"
        exit 1
    fi

    echo "==> Stopping running instance..."
    pkill -f "${APP_NAME}.app" 2>/dev/null || true
    sleep 1

    echo "==> Installing to /Applications..."
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$app_path" "/Applications/${APP_NAME}.app"

    echo "==> Launching ${APP_NAME}..."
    open "/Applications/${APP_NAME}.app"

    echo ""
    echo "Done! ${APP_NAME} is now installed and running."
    echo "Location: /Applications/${APP_NAME}.app"
}

# B: Create DMG
deploy_dmg() {
    build

    local app_path
    app_path=$(find_app)
    if [[ ! -d "$app_path" ]]; then
        echo "Error: ${APP_NAME}.app not found at $app_path"
        exit 1
    fi

    local staging="/tmp/${APP_NAME}-dmg-staging"

    echo "==> Preparing DMG contents..."
    rm -rf "$staging"
    mkdir -p "$staging"
    cp -R "$app_path" "$staging/"
    ln -s /Applications "$staging/Applications"

    echo "==> Creating DMG..."
    rm -f "$DMG_OUTPUT"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$staging" \
        -ov -format UDZO \
        "$DMG_OUTPUT" 2>&1 | grep -v "^$"

    rm -rf "$staging"

    local size
    size=$(du -h "$DMG_OUTPUT" | cut -f1 | xargs)

    echo ""
    echo "Done! DMG created:"
    echo "  File: $DMG_OUTPUT"
    echo "  Size: $size"
    echo ""
    echo "Note: This DMG is not code-signed."
    echo "Recipients need to right-click → Open, or run:"
    echo "  xattr -cr ${APP_NAME}.app"
}

# Usage
usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  app    Build and install to /Applications (personal use)"
    echo "  dmg    Build and create DMG on Desktop (for sharing)"
    echo "  both   Do both: install + create DMG"
    echo ""
    echo "Examples:"
    echo "  ./deploy.sh app"
    echo "  ./deploy.sh dmg"
    echo "  ./deploy.sh both"
}

case "${1:-}" in
    app)
        deploy_app
        ;;
    dmg)
        deploy_dmg
        ;;
    both)
        deploy_app
        echo ""
        echo "---"
        echo ""
        deploy_dmg
        ;;
    *)
        usage
        exit 1
        ;;
esac
