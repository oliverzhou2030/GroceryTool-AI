#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
PROJECT="$PROJECT_ROOT/GroceryToolAI/GroceryToolAI.xcodeproj"
DERIVED_DATA="/tmp/GroceryToolAI-MacDerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/GroceryToolAI.app"
EXECUTABLE="$APP/Contents/MacOS/GroceryToolAI"
OPENPRICEENGINE_KEY_FILE="$PROJECT_ROOT/.openpricengine-key"
GOOGLE_OAUTH_FILE="$PROJECT_ROOT/.google-oauth-client.json"
DEEPSEEK_KEY_FILE="$PROJECT_ROOT/.deepseek-key"
DEVICE_NAME="${1:-iPhone 17 Pro}"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

xcodebuild -quiet -project "$PROJECT" -scheme GroceryToolAI -destination "platform=macOS" -derivedDataPath "$DERIVED_DATA" build CODE_SIGNING_ALLOWED=NO

DEVICE_ID="$(xcrun simctl list devices available | sed -n "s/^[[:space:]]*$DEVICE_NAME (\([0-9A-F-]*\)).*/\1/p" | head -1)"
if [[ -n "$DEVICE_ID" ]]; then
  SIMULATOR_DATA_CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" com.oliverzhou2030.GroceryToolAI data 2>/dev/null || true)"
  if [[ -z "$SIMULATOR_DATA_CONTAINER" ]]; then
    print "Installing the iPhone app and recovering its receipt history..."
    "$PROJECT_ROOT/run-iphone.command" "$DEVICE_NAME"
    SIMULATOR_DATA_CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" com.oliverzhou2030.GroceryToolAI data 2>/dev/null || true)"
  fi
  if [[ -n "$SIMULATOR_DATA_CONTAINER" ]]; then
    SHARED_DATA_DIRECTORY="$SIMULATOR_DATA_CONTAINER/Library/Application Support/GroceryToolAI"
    SHARED_DATA_SIZE="$(stat -f %z "$SHARED_DATA_DIRECTORY/user-data.json" 2>/dev/null || print 0)"
    DEVICE_DATA_ROOT="$HOME/Library/Developer/CoreSimulator/Devices/$DEVICE_ID/data"
    RECOVERY_DATA_DIRECTORY=""
    RECOVERY_DATA_SIZE=0
    for candidate_json in "$DEVICE_DATA_ROOT"/Containers/Data/Application/*/Library/Application\ Support/GroceryToolAI/user-data.json(N); do
      candidate_size="$(stat -f %z "$candidate_json" 2>/dev/null || print 0)"
      if (( candidate_size > RECOVERY_DATA_SIZE )); then
        RECOVERY_DATA_SIZE="$candidate_size"
        RECOVERY_DATA_DIRECTORY="${candidate_json:h}"
      fi
    done
    if [[ -n "$RECOVERY_DATA_DIRECTORY" && "$RECOVERY_DATA_DIRECTORY" != "$SHARED_DATA_DIRECTORY" && "$RECOVERY_DATA_SIZE" -gt "$SHARED_DATA_SIZE" ]]; then
      mkdir -p "$SHARED_DATA_DIRECTORY"
      cp "$RECOVERY_DATA_DIRECTORY/user-data.json" "$SHARED_DATA_DIRECTORY/user-data.json"
      if [[ -d "$RECOVERY_DATA_DIRECTORY/ReceiptImages" ]]; then
        mkdir -p "$SHARED_DATA_DIRECTORY/ReceiptImages"
        ditto "$RECOVERY_DATA_DIRECTORY/ReceiptImages" "$SHARED_DATA_DIRECTORY/ReceiptImages"
      fi
      print "Recovered existing receipt history and files into the active Simulator app."
    fi
    export GROCERYTOOL_SHARED_DATA_DIRECTORY="$SHARED_DATA_DIRECTORY"
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

if [[ -r "$GOOGLE_OAUTH_FILE" ]]; then
  export GOOGLE_OAUTH_CREDENTIALS_FILE="$GOOGLE_OAUTH_FILE"
  print "Google Sheets: configured"
else
  print "Google Sheets: not configured (add the OAuth JSON to $GOOGLE_OAUTH_FILE)"
fi

if [[ -r "$DEEPSEEK_KEY_FILE" ]]; then
  export DEEPSEEK_API_KEY="$(<"$DEEPSEEK_KEY_FILE")"
  print "Grocery AI: configured"
else
  print "Grocery AI: not configured (add the key to $DEEPSEEK_KEY_FILE)"
fi

while IFS= read -r running_pid; do
  [[ -n "$running_pid" ]] && kill "$running_pid" 2>/dev/null || true
done < <(pgrep -f '/GroceryToolAI\.app/Contents/MacOS/GroceryToolAI$' || true)
sleep 0.5
LAUNCH_ENV=()
if [[ -n "${GROCERYTOOL_SHARED_DATA_DIRECTORY:-}" ]]; then
  LAUNCH_ENV+=(--env "GROCERYTOOL_SHARED_DATA_DIRECTORY=$GROCERYTOOL_SHARED_DATA_DIRECTORY")
fi
if [[ -n "${OPENPRICEENGINE_API_KEY:-}" ]]; then
  LAUNCH_ENV+=(--env "OPENPRICEENGINE_API_KEY=$OPENPRICEENGINE_API_KEY")
fi
if [[ -n "${GOOGLE_OAUTH_CREDENTIALS_FILE:-}" ]]; then
  LAUNCH_ENV+=(--env "GOOGLE_OAUTH_CREDENTIALS_FILE=$GOOGLE_OAUTH_CREDENTIALS_FILE")
fi
if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
  LAUNCH_ENV+=(--env "DEEPSEEK_API_KEY=$DEEPSEEK_API_KEY")
fi
open -n -F "${LAUNCH_ENV[@]}" "$APP"
print "GroceryTool AI is open on Mac."
