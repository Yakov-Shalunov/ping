#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/env.sh" ]; then
    echo "Error: env.sh not found. Copy env.sh.example to env.sh and fill in your team ID."
    exit 1
fi

source "$SCRIPT_DIR/env.sh"

# Generate Xcode project
xcodegen generate --spec "$SCRIPT_DIR/project.yml"

# Default to macOS if no platform specified
PLATFORM="${1:-macOS}"

case "$PLATFORM" in
    macOS)
        xcodebuild -project "$SCRIPT_DIR/Ping.xcodeproj" -scheme Ping \
            -destination 'platform=macOS' build
        ;;
    iOS)
        DEVICE="${2:-iPhone 16}"
        xcodebuild -project "$SCRIPT_DIR/Ping.xcodeproj" -scheme Ping \
            -destination "platform=iOS Simulator,name=$DEVICE" build
        ;;
    *)
        echo "Usage: $0 [macOS|iOS] [device-name]"
        exit 1
        ;;
esac
