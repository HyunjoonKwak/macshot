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

# Version management
current_version() {
    grep 'MARKETING_VERSION' "$PROJECT_DIR/macshot.xcodeproj/project.pbxproj" | head -1 | sed 's/.*= //;s/;.*//'
}

set_version() {
    local new_ver="$1"
    if [[ ! "$new_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Version must be in X.Y.Z format (e.g. 1.2.0)"
        exit 1
    fi

    local old_ver
    old_ver=$(current_version)

    sed -i '' "s/MARKETING_VERSION = ${old_ver}/MARKETING_VERSION = ${new_ver}/g" \
        "$PROJECT_DIR/macshot.xcodeproj/project.pbxproj"
    sed -i '' "s/CURRENT_PROJECT_VERSION = ${old_ver}/CURRENT_PROJECT_VERSION = ${new_ver}/g" \
        "$PROJECT_DIR/macshot.xcodeproj/project.pbxproj"

    echo "Version changed: ${old_ver} → ${new_ver}"
}

bump_version() {
    local part="$1"
    local ver
    ver=$(current_version)
    local major minor patch
    IFS='.' read -r major minor patch <<< "$ver"

    case "$part" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "Error: Use 'major', 'minor', or 'patch'"; exit 1 ;;
    esac

    set_version "${major}.${minor}.${patch}"
}

# Usage
usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  app              Build and install to /Applications"
    echo "  dmg              Build and create DMG on Desktop"
    echo "  both             Do both: install + create DMG"
    echo "  version          Show current version"
    echo "  version <X.Y.Z>  Set version (e.g. 1.2.0)"
    echo "  bump <part>      Bump version (major/minor/patch)"
    echo ""
    echo "Examples:"
    echo "  ./deploy.sh app"
    echo "  ./deploy.sh dmg"
    echo "  ./deploy.sh version 2.0.0"
    echo "  ./deploy.sh bump patch    # 1.0.0 → 1.0.1"
    echo "  ./deploy.sh bump minor    # 1.0.1 → 1.1.0"
    echo "  ./deploy.sh bump major    # 1.1.0 → 2.0.0"
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
    version)
        if [[ -z "${2:-}" ]]; then
            echo "ScreenShot v$(current_version)"
        else
            set_version "$2"
        fi
        ;;
    bump)
        bump_version "${2:-patch}"
        ;;
    *)
        usage
        exit 1
        ;;
esac
