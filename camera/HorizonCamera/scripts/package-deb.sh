#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scheme="${1:-rootful}"; style="${2:-classic}"
case "$scheme" in rootful) prefix=''; architecture='iphoneos-arm'; deployment='12.0';; rootless) prefix='/var/jb'; architecture='iphoneos-arm64'; deployment='15.0';; *) exit 1;; esac
if [ "$style" = o2 ]; then product='NeloraO2'; bundle='com.theipos.o2camera'; label='Камера'; icon='O2Icon'; else product='HorizonCamera'; bundle='com.theipos.camera'; label='Nelora Camera'; icon='AppIcon'; fi
if [ "$style" = o2 ] && [ -f Assets.xcassets/O2Icon.appiconset/Original.png ]; then
 for size in 40 58 60 80 87 120 180 1024; do sips -z "$size" "$size" Assets.xcassets/O2Icon.appiconset/Original.png --out "Assets.xcassets/O2Icon.appiconset/Icon-$size.png" >/dev/null; done
fi
build="$PWD/build/deb-$scheme-$style-$(date +%s)"
mkdir -p "$build/stage/DEBIAN" "$build/stage$prefix/Applications" "$PWD/packages"
xcodebuild -project HorizonCamera.xcodeproj -scheme HorizonCamera -configuration Release -sdk iphoneos \
 -derivedDataPath "$build/DerivedData" CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET="$deployment" \
 ARCHS=arm64 ONLY_ACTIVE_ARCH=NO PRODUCT_NAME="$product" PRODUCT_BUNDLE_IDENTIFIER="$bundle" \
 ASSETCATALOG_COMPILER_APPICON_NAME="$icon" \
 OTHER_SWIFT_FLAGS="-Xfrontend -disable-autolink-framework -Xfrontend SwiftUI" OTHER_LDFLAGS="-weak_framework SwiftUI" build
app="$build/stage$prefix/Applications/$product.app"
ditto "$build/DerivedData/Build/Products/Release-iphoneos/$product.app" "$app"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $label" "$app/Info.plist"
python3 ../../scripts/verify-ios12.py "$app"
while IFS= read -r -d '' binary; do if file "$binary" | grep -q 'Mach-O'; then ldid -S "$binary"; fi; done < <(find "$app" -type f -print0)
chmod 755 "$app/$product"
cat > "$build/stage/DEBIAN/control" <<EOF
Package: $bundle
Name: $label
Version: 0.4.4
Architecture: $architecture
Depends: firmware (>= $deployment)
Conflicts: com.theipos.motion, com.theipos.glass
Maintainer: Nelora
Author: Nelora
Section: Tweaks
Description: Standalone camera with bounded GPU preview, gallery and software horizon lock. O2 demo labels do not change real recording format.
EOF
cat > "$build/stage/DEBIAN/postinst" <<EOF
#!/bin/sh
for cache in /var/jb/usr/bin/uicache /usr/bin/uicache; do
 if [ -x "\$cache" ]; then "\$cache" -p '$prefix/Applications/$product.app' || true; break; fi
done
exit 0
EOF
cat > "$build/stage/DEBIAN/postrm" <<'EOF'
#!/bin/sh
for cache in /var/jb/usr/bin/uicache /usr/bin/uicache; do
 if [ -x "$cache" ]; then "$cache" -a || true; break; fi
done
exit 0
EOF
chmod 755 "$build/stage/DEBIAN/postinst" "$build/stage/DEBIAN/postrm"
dpkg-deb -Zgzip --build "$build/stage" "$PWD/packages/${bundle}_0.4.4_${architecture}.deb"
