#!/bin/bash
set -euo pipefail
TASK_ROOT="${JSB_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
TEST_ROOT="${JSB_BUILD_ROOT:?Set JSB_BUILD_ROOT to private generated BuildInputs}"
APP="${JSB_APP:?Set JSB_APP to an expendable staged JSAB.app under /private/tmp}"
IDENTITY="${JSB_IDENTITY:?Set JSB_IDENTITY to your signing identity}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
case "$APP" in /private/tmp/*) ;; *) echo "Use a staging app under /private/tmp" >&2; exit 1;; esac
xcrun --sdk iphoneos clang -fobjc-arc -target arm64-apple-ios17.0 -dynamiclib \
  -install_name @rpath/libShim_AppKit.dylib -Wno-incompatible-library-redeclaration \
  -framework Foundation -Wl,-reexport_framework,UIKit -framework QuartzCore \
  -framework CoreGraphics -framework CoreAudio -framework Metal -framework GameController -lc++ \
  "$TEST_ROOT/shims/Shim_AppKit.m" \
  "$TASK_ROOT/compatibility/jsab-keyboard/shim/overrides/AppKit.m" \
  "$TASK_ROOT"/compatibility/jsab-keyboard/shim/overrides/AppKit_*.m \
  "$TASK_ROOT/compatibility/standalone/TouchControls.m" \
  "$TASK_ROOT/compatibility/standalone/SaveBackend.m" \
  -o "$APP/Frameworks/libShim_AppKit.dylib"
# Regenerate the one generated display shim entry now implemented by the override.
sed '/CGDisplayModeCopyPixelEncoding/d' "$TEST_ROOT/shims/Shim_CoreGraphics.m" > "$TEST_ROOT/shims/JSB_CoreGraphics.m"
xcrun --sdk iphoneos clang -fobjc-arc -target arm64-apple-ios17.0 -dynamiclib \
  -install_name @rpath/libShim_CoreGraphics.dylib -framework Foundation -framework UIKit \
  -framework Metal -Wl,-reexport_framework,CoreGraphics \
  "$TEST_ROOT/shims/JSB_CoreGraphics.m" "$TASK_ROOT/compatibility/jsab-keyboard/shim/overrides/CoreGraphics.m" \
  -o "$APP/Frameworks/libShim_CoreGraphics.dylib"
xcrun codesign --force --sign "$IDENTITY" "$APP/Frameworks/libShim_CoreGraphics.dylib"
xcrun --sdk iphoneos clang -fobjc-arc -target arm64-apple-ios17.0 -dynamiclib \
  -install_name @rpath/libShim_CoreVideo.dylib -framework Foundation -Wl,-reexport_framework,CoreVideo \
  "$TEST_ROOT/shims/Shim_CoreVideo.m" "$TASK_ROOT/compatibility/jsab-keyboard/shim/overrides/CoreVideo_DisplayLink.m" \
  -o "$APP/Frameworks/libShim_CoreVideo.dylib"
xcrun codesign --force --sign "$IDENTITY" "$APP/Frameworks/libShim_CoreVideo.dylib"
xcrun --sdk iphoneos clang -fobjc-arc -target arm64-apple-ios17.0 -dynamiclib \
  -install_name @rpath/libJSBAudio.dylib -framework Foundation -framework AVFoundation \
  -Wl,-reexport_framework,AudioToolbox -Wl,-reexport_framework,CoreAudio \
  "$TASK_ROOT/compatibility/standalone/AudioCompat.m" -o "$APP/Frameworks/libJSBAudio.dylib"
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -dynamiclib \
  -install_name @rpath/libJSBOutput.dylib -Wl,-reexport_library,"$APP/Frameworks/libJSBAudio.dylib" \
  "$TASK_ROOT/compatibility/standalone/AudioOutput.c" -o "$APP/Frameworks/libJSBOutput.dylib"
cp "${JSB_BASE_UNITY:-$TEST_ROOT/baseUnityPlayer.dylib}" "$APP/Mac/Contents/Frameworks/UnityPlayer.dylib"
xcrun install_name_tool -change /System/Library/Frameworks/CoreAudio.framework/CoreAudio @rpath/libJSBAudio.dylib \
  -change @rpath/libShim_AudioUnit.dylib @rpath/libJSBOutput.dylib "$APP/Mac/Contents/Frameworks/UnityPlayer.dylib"
if [ "${JSB_LC_SYSTEM_HEAP:-0}" = "1" ]; then
  python3 "$TASK_ROOT/compatibility/standalone/patch_lc_allocator.py" "$APP/Mac/Contents/Frameworks/UnityPlayer.dylib"
fi
if [ "${JSB_VSYNC_GUARD:-1}" = "1" ]; then
  python3 "$TASK_ROOT/compatibility/standalone/patch_vsync_wait.py" "$APP/Mac/Contents/Frameworks/UnityPlayer.dylib"
fi
xcrun codesign --force --sign "$IDENTITY" "$APP/Mac/Contents/Frameworks/UnityPlayer.dylib"
xcrun codesign --force --sign "$IDENTITY" "$APP/Frameworks/libJSBAudio.dylib"
xcrun codesign --force --sign "$IDENTITY" "$APP/Frameworks/libJSBOutput.dylib"
xcrun codesign --force --sign "$IDENTITY" "$APP/Frameworks/libShim_AppKit.dylib"
xcrun codesign --force --sign "$IDENTITY" --entitlements "$TEST_ROOT/entitlements.plist" "$APP"
if [ "${JSB_SKIP_DEVICE:-1}" = "1" ]; then exit 0; fi
xcrun devicectl device install app --device "${UDID:?Set UDID for device installation}" "$APP"
xcrun devicectl device process launch --device "${UDID:?Set UDID for device installation}" \
  --terminate-existing --console "${JSB_BUNDLE_ID:?Set JSB_BUNDLE_ID for device launch}" -- -force-metal -logFile -
