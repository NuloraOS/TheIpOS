#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo 'Нужен Mac с Xcode и установленным iPhoneOS SDK.' >&2; exit 1
fi
mkdir -p build
if [[ "${1:-}" == "--unsigned" ]]; then
  xcodebuild -project HorizonCamera.xcodeproj -scheme HorizonCamera -configuration Release -sdk iphoneos \
    -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
  echo 'Собран неподписанный .app. На iPhone он не установится без подписи.'
  exit 0
fi
: "${DEVELOPMENT_TEAM:?Укажите DEVELOPMENT_TEAM своей учётной записи Apple Developer}"
: "${EXPORT_OPTIONS_PLIST:?Укажите путь к своему ExportOptions.plist}"
xcodebuild -project HorizonCamera.xcodeproj -scheme HorizonCamera -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/HorizonCamera.xcarchive \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/HorizonCamera.xcarchive \
  -exportPath build/IPA -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" -allowProvisioningUpdates
echo 'IPA находится в build/IPA. Секретные ключи в проект не включаются.'
