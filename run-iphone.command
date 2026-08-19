#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
PROJECT="$PROJECT_ROOT/GroceryToolAI/GroceryToolAI.xcodeproj"
DERIVED_DATA="/tmp/GroceryToolAI-DerivedData"
DEVICE_NAME="${1:-iPhone 17 Pro}"
SIMULATOR_LATITUDE="${GROCERYTOOL_LATITUDE:-40.789}"
SIMULATOR_LONGITUDE="${GROCERYTOOL_LONGITUDE:--73.702}"
OPENPRICEENGINE_KEY_FILE="$PROJECT_ROOT/.openpricengine-key"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

DEVICE_ID="$(xcrun simctl list devices available | sed -n "s/^[[:space:]]*$DEVICE_NAME (\([0-9A-F-]*\)).*/\1/p" | head -1)"
if [[ -z "$DEVICE_ID" ]]; then
  print "Could not find an available '$DEVICE_NAME' simulator."
  print "Open Xcode > Settings > Components and install an iOS simulator first."
  exit 1
fi

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl location "$DEVICE_ID" set "$SIMULATOR_LATITUDE,$SIMULATOR_LONGITUDE"
xcodebuild -quiet -project "$PROJECT" -scheme GroceryToolAI -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath "$DERIVED_DATA" build CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$DEVICE_ID" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/GroceryToolAI.app"
open -a Simulator
if [[ -r "$OPENPRICEENGINE_KEY_FILE" ]]; then
  OPENPRICEENGINE_API_KEY="$(<"$OPENPRICEENGINE_KEY_FILE")"
  SIMCTL_CHILD_OPENPRICEENGINE_API_KEY="$OPENPRICEENGINE_API_KEY" \
    xcrun simctl launch --terminate-running-process "$DEVICE_ID" com.oliverzhou2030.GroceryToolAI
  print "OpenPriceEngine: configured"
else
  xcrun simctl launch --terminate-running-process "$DEVICE_ID" com.oliverzhou2030.GroceryToolAI
  print "OpenPriceEngine: not configured (add the key to $OPENPRICEENGINE_KEY_FILE)"
fi
print "Simulator location: $SIMULATOR_LATITUDE, $SIMULATOR_LONGITUDE"
