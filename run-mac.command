#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
PROJECT="$PROJECT_ROOT/GroceryToolAI/GroceryToolAI.xcodeproj"
DERIVED_DATA="/tmp/GroceryToolAI-MacDerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/GroceryToolAI.app"
EXECUTABLE="$APP/Contents/MacOS/GroceryToolAI"
OPENPRICEENGINE_KEY_FILE="$PROJECT_ROOT/.openpricengine-key"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

xcodebuild -quiet -project "$PROJECT" -scheme GroceryToolAI -destination "platform=macOS" -derivedDataPath "$DERIVED_DATA" build CODE_SIGNING_ALLOWED=NO

if [[ -r "$OPENPRICEENGINE_KEY_FILE" ]]; then
  export OPENPRICEENGINE_API_KEY="$(<"$OPENPRICEENGINE_KEY_FILE")"
  print "OpenPriceEngine: configured"
else
  print "OpenPriceEngine: not configured (add the key to $OPENPRICEENGINE_KEY_FILE)"
fi

nohup "$EXECUTABLE" > /tmp/GroceryToolAI-mac.log 2>&1 &!
print "GroceryTool AI is open on Mac."
