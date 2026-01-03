#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_PATH="$PROJECT_ROOT/Ogenblick/Resources/Secrets.plist"

: "${ACR_HOST:?ACR_HOST not set}"
: "${ACR_ACCESS_KEY:?ACR_ACCESS_KEY not set}"
: "${ACR_ACCESS_SECRET:?ACR_ACCESS_SECRET not set}"

cat > "$SECRETS_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>host</key>
  <string>${ACR_HOST}</string>
  <key>accessKey</key>
  <string>${ACR_ACCESS_KEY}</string>
  <key>accessSecret</key>
  <string>${ACR_ACCESS_SECRET}</string>
</dict>
</plist>
PLIST

echo "Secrets.plist written to $SECRETS_PATH"
