#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
cd "$ROOT"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --spec project.yml --project OpenSimFixture.xcodeproj
  xcodebuild -project OpenSimFixture.xcodeproj -scheme OpenSimFixture -configuration Debug \
    -sdk iphonesimulator -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
  print "$ROOT/build/Build/Products/Debug-iphonesimulator/OpenSimFixture.app"
  exit 0
fi

print -u2 "xcodegen not found; falling back to swiftc fixture build"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
APP="$ROOT/build/OpenSimFixture.app"
rm -rf "$APP"
mkdir -p "$APP"
xcrun --sdk iphonesimulator swiftc \
  -sdk "$SDK" \
  -target arm64-apple-ios17.0-simulator \
  -module-name OpenSimFixture \
  -framework UIKit \
  -emit-executable \
  Sources/AppDelegate.swift Sources/SceneDelegate.swift \
  Sources/FixtureViewController.swift Sources/DetailsViewController.swift \
  -o "$APP/OpenSimFixture" >&2

cp Info.plist "$APP/Info.plist"

codesign --force --sign - "$APP" >&2 || true
print "$APP"
