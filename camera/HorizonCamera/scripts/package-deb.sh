#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Нужен iOS toolchain с Xcode.' >&2; exit 1; }
command -v ldid >/dev/null || { echo 'Нужен ldid.' >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo 'Нужен dpkg-deb.' >&2; exit 1; }
scheme="${1:-rootful}"
case "$scheme" in
  rootful) prefix=''; architecture='iphoneos-arm'; deployment='12.0' ;;
  rootless) prefix='/var/jb'; architecture='iphoneos-arm64'; deployment='15.0' ;;
  *) echo 'Выберите rootful или rootless' >&2; exit 1 ;;
esac
build="$PWD/build/deb-$scheme-$(date +%s)"
mkdir -p "$build/stage/DEBIAN" "$build/stage$prefix/Applications" "$PWD/packages"
xcodebuild -project HorizonCamera.xcodeproj -scheme HorizonCamera -configuration Release -sdk iphoneos \
  -derivedDataPath "$build/DerivedData" CODE_SIGNING_ALLOWED=NO \
  IPHONEOS_DEPLOYMENT_TARGET="$deployment" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build
app="$build/stage$prefix/Applications/HorizonCamera.app"
ditto "$build/DerivedData/Build/Products/Release-iphoneos/HorizonCamera.app" "$app"
# Sign every embedded Mach-O, then the executable. No trust-cache or kernel modifications.
while IFS= read -r -d '' binary; do
  if file "$binary" | grep -q 'Mach-O'; then ldid -S "$binary"; fi
done < <(find "$app" -type f -print0)
chmod 755 "$app/HorizonCamera"
cat > "$build/stage/DEBIAN/control" <<EOF
Package: com.theipos.camera
Name: Nulora Camera
Version: 0.2.0
Architecture: $architecture
Depends: firmware (>= $deployment)
Maintainer: Nulora
Author: Nulora
Section: Camera
Description: Camera with software horizon lock. Standalone app, no system camera injection.
EOF
cat > "$build/stage/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
for cache in /var/jb/usr/bin/uicache /usr/bin/uicache; do
  if [ -x "\$cache" ]; then "\$cache" -p '$prefix/Applications/HorizonCamera.app' || true; break; fi
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
dpkg-deb -Zgzip --build "$build/stage" "$PWD/packages/com.theipos.camera_0.2.0_${architecture}.deb"
echo "Готов DEB для $scheme; установка на телефон здесь не выполняется."
