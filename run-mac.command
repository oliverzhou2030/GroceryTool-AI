#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
PROJECT="$PROJECT_ROOT/GroceryToolAI/GroceryToolAI.xcodeproj"
DERIVED_DATA="/tmp/GroceryToolAI-MacDerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/GroceryToolAI.app"
EXECUTABLE="$APP/Contents/MacOS/GroceryToolAI"
OPENPRICEENGINE_KEY_FILE="$PROJECT_ROOT/.openpricengine-key"
DEVICE_NAME="${1:-iPhone 17 Pro}"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

xcodebuild -quiet -project "$PROJECT" -scheme GroceryToolAI -destination "platform=macOS" -derivedDataPath "$DERIVED_DATA" build CODE_SIGNING_ALLOWED=NO

DEVICE_ID="$(xcrun simctl list devices available | sed -n "s/^[[:space:]]*$DEVICE_NAME (\([0-9A-F-]*\)).*/\1/p" | head -1)"
if [[ -n "$DEVICE_ID" ]]; then
  SIMULATOR_DATA_CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" com.oliverzhou2030.GroceryToolAI data 2>/dev/null || true)"
  if [[ -n "$SIMULATOR_DATA_CONTAINER" ]]; then
    export GROCERYTOOL_SHARED_DATA_DIRECTORY="$SIMULATOR_DATA_CONTAINER/Library/Application Support/GroceryToolAI"
    print "Receipt sync: Mac + $DEVICE_NAME Simulator"
  else
    print "Receipt sync: run ./run-iphone.command once to install the iPhone app"
  fi
fi

if [[ -r "$OPENPRICEENGINE_KEY_FILE" ]]; then
  export OPENPRICEENGINE_API_KEY="$(<"$OPENPRICEENGINE_KEY_FILE")"
  print "OpenPriceEngine: configured"
else
  print "OpenPriceEngine: not configured (add the key to $OPENPRICEENGINE_KEY_FILE)"
fi

CANONICAL_EXECUTABLE="${EXECUTABLE:A}"
while IFS= read -r running_pid; do
  [[ -n "$running_pid" ]] && kill "$running_pid" 2>/dev/null || true
done < <(pgrep -f "^${CANONICAL_EXECUTABLE}$" || true)
sleep 0.5
nohup "$EXECUTABLE" > /tmp/GroceryToolAI-mac.log 2>&1 &!
print "GroceryTool AI is open on Mac."
