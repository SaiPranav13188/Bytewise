#!/bin/zsh
# Builds a Release copy of Bytewise, signs it with the hardened runtime,
# checks the signature and sandbox, then zips it and writes a SHA-256
# checksum to publish next to the download.
#
# Usage: Scripts/release.sh [signing identity]
# Without an identity the app is signed ad hoc ("-"), which is fine for
# GitHub downloads that are not notarized.
set -euo pipefail

identity="${1:--}"
root="${0:A:h:h}"
out="$root/build/release"
app="$out/Build/Products/Release/Bytewise.app"

rm -rf "$out"
xcodebuild -project "$root/Bytewise.xcodeproj" -scheme Bytewise -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$out" build | grep -E "BUILD|error:"

# Re-sign with the hardened runtime, keeping the entitlements Xcode set.
entitlements="$out/entitlements.plist"
codesign -d --entitlements - --xml "$app" > "$entitlements"
# Debugger access is only for development builds.
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$entitlements" 2>/dev/null || true
codesign --force --options runtime --timestamp=none \
    --entitlements "$entitlements" --sign "$identity" "$app"

# Refuse to publish a build that lost its protections.
codesign --verify --strict --verbose=1 "$app"
info=$(codesign -dv "$app" 2>&1)
granted=$(codesign -d --entitlements - "$app" 2>/dev/null)
[[ "$info" == *runtime* ]] || { echo "Hardened runtime missing"; exit 1; }
[[ "$granted" == *com.apple.security.app-sandbox* ]] || { echo "Sandbox missing"; exit 1; }
if [[ "$granted" == *network.client* || "$granted" == *network.server* || "$granted" == *get-task-allow* ]]; then
    echo "Unexpected entitlement"; exit 1
fi

version=$(defaults read "$app/Contents/Info" CFBundleShortVersionString)
zip="$root/build/Bytewise-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
(cd "${zip:h}" && shasum -a 256 "${zip:t}" > "${zip:t}.sha256")

echo "Built $zip"
cat "$zip.sha256"
