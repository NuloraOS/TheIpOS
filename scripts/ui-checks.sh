#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p ui-checks
xcrun simctl list devices available --json > "$RUNNER_TEMP/devices.json"
read -r device state < <(python3 - "$RUNNER_TEMP/devices.json" <<'PY'
import json,sys
items=[d for group in json.load(open(sys.argv[1]))['devices'].values() for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
assert items,'No iPhone simulator installed'
d=next((d for d in items if 'SE' in d['name']),items[0])
print(d['udid'],d['state'])
PY
)
if [ "$state" != Booted ]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
for style in classic o2; do
 if [ "$style" = o2 ]; then product=NeloraO2; bundle=com.theipos.o2camera; icon=O2Icon; else product=HorizonCamera; bundle=com.theipos.camera; icon=AppIcon; fi
 build="$RUNNER_TEMP/ui-$style"
 xcodebuild -project camera/HorizonCamera/HorizonCamera.xcodeproj -scheme HorizonCamera -configuration Debug \
 -sdk iphonesimulator -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$build" \
 CODE_SIGNING_ALLOWED=NO PRODUCT_NAME="$product" PRODUCT_BUNDLE_IDENTIFIER="$bundle" ASSETCATALOG_COMPILER_APPICON_NAME="$icon" build > "$RUNNER_TEMP/ui-$style-build.log" 2>&1 || { tail -n 80 "$RUNNER_TEMP/ui-$style-build.log"; exit 1; }
 xcrun simctl install "$device" "$build/Build/Products/Debug-iphonesimulator/$product.app"
 xcrun simctl launch --terminate-running-process "$device" "$bundle" --ui-probe
 container=$(xcrun simctl get_app_container "$device" "$bundle" data)
 for i in $(seq 1 45); do if [ -f "$container/Documents/probe-done.txt" ]; then break; fi; sleep 1; done
 cp "$container/Documents/ui-probe.png" "ui-checks/$style-camera.png"
 cp "$container/Documents/gallery-probe.png" "ui-checks/$style-gallery.png"
 cp "$container/Documents/ui-probe.txt" "ui-checks/$style-interface.txt"
 cp "$container/Documents/video-probe.txt" "ui-checks/$style-video.txt"
 python3 - "$container/Documents/ui-probe.txt" "$container/Documents/video-probe.txt" <<'PY'
import pathlib,sys
for name in sys.argv[1:]:
 report=pathlib.Path(name).read_text()
 print(report)
 assert report.startswith('PASS'),report
PY
 xcrun simctl terminate "$device" "$bundle"
done
