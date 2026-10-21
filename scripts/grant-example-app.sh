#!/bin/bash
# grant-example as a real app: its own bundle id (so tccd keeps its own
# records, never the terminal's), a harmless launch agent inside (so its
# background-service grant has something to install), signed with the team's
# Apple Development identity (an unsigned bundle can register no agent).
# Opens it from build/, where the helper's row offers "move to Applications".
# `grant reset grant-example` takes it back to square one.
set -euo pipefail

id="garden.untitled.grant-example"
app="build/grant-example.app"
agent="$id.helper.plist"

swift build -c release --product grant-example
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Library/LaunchAgents"
cp .build/release/grant-example "$app/Contents/MacOS/grant-example"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleName</key><string>grant example</string>
  <key>CFBundleExecutable</key><string>grant-example</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSMicrophoneUsageDescription</key><string>The example asks for the microphone to show the grant flow; it records nothing.</string>
  <key>NSCameraUsageDescription</key><string>The example asks for the camera to show the grant flow; it records nothing.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>The example asks for speech recognition to show the grant flow; it recognizes nothing.</string>
  <key>NSMotionUsageDescription</key><string>The example asks for headphone motion to show the grant flow; it reads nothing.</string>
</dict></plist>
EOF

# The helper: the same binary idling (--helper), started at login once
# approved. It does nothing; it exists to be installed.
cat > "$app/Contents/Library/LaunchAgents/$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$id.helper</string>
  <key>BundleProgram</key><string>Contents/MacOS/grant-example</string>
  <key>ProgramArguments</key><array><string>grant-example</string><string>--helper</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
EOF

# Under the hardened runtime macOS denies the microphone and the camera
# WITHOUT asking unless the signature carries these entitlements.
entitlements="$(mktemp -t grant-example).plist"
cat > "$entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.device.camera</key><true/>
</dict></plist>
EOF

identity="$(ship identity --team G387QW47LV)"
codesign --force --options runtime --timestamp=none --entitlements "$entitlements" --sign "$identity" "$app"
rm "$entitlements"
codesign --verify --strict "$app"
echo "built $app (signed $identity)"

# Once moved to an Applications folder (the helper's flow, for everyone or
# just this account), that copy IS the app: it is replaced with this build and
# opened, so two copies of one bundle id never run different code (`open -b`
# and `grant reset` pick the installed one).
installed=""
for folder in /Applications "$HOME/Applications"; do
    [ -d "$folder/grant-example.app" ] && { installed="$folder/grant-example.app"; break; }
done
pkill -f "grant-example.app/Contents/MacOS/grant-example" || true
if [ -n "$installed" ]; then
    trash "$installed"
    cp -R "$app" "$installed"
    echo "replaced $installed"
    open "$installed"
else
    open "$app"
fi
