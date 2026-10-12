# Build guide

## 1. Prepare the tools and private inputs

Use an Apple Silicon Mac with Xcode and its iPhoneOS SDK. Select Xcode:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --sdk iphoneos --show-sdk-path
xcrun devicectl list devices
security find-identity -v -p codesigning
```

The verified environment used Xcode 27.0. The converter has a historical 27.1 SDK-version tag; review it against your SDK before new conversion rather than treating that tag as a proven minimum. These direct compiler helpers do not require Homebrew or xcodegen. External source dependencies may have additional build requirements.

Private inputs belong outside the clone:

- A legally obtained Mac JSAB 1.6.50 app with ARM64 main executable, UnityPlayer and IL2CPP GameAssembly. Confirm rather than trusting the filename. The inspected engine was Unity 2020.3.36f1 (71f96b79b9f0).
- Your own signing identity, bundle ID, provisioning profile and entitlements matching that identity/device.
- For the archive rebuild: your private converted app/IPA, generated `BuildInputs/shims/*.m`, `BuildInputs/entitlements.plist`, and unpatched converted `BuildInputs/baseUnityPlayer.dylib`.

A Linux x86-64 library or Android ARM64 ELF library cannot be dropped into an iOS Mach-O app. Android data from another Unity version is not a substitute for the matching Mac assets.

Inspect the Mac app (replace the example path):

```sh
export MAC_APP='/path/to/your/JSB.app'
file "$MAC_APP/Contents/MacOS/JSB"
lipo -archs "$MAC_APP/Contents/Frameworks/UnityPlayer.dylib"
find "$MAC_APP/Contents" -iname '*GameAssembly*' -o -iname '*mono*'
plutil -p "$MAC_APP/Contents/Info.plist"
```

The executable name can differ; read `CFBundleExecutable`. Mono-only builds do not establish the verified JIT-disabled route.

## 2. Understand the initial conversion

The general converter copies the Mac bundle, keeps its original resources under `Mac/Contents`, thins Mach-O files to ARM64, retags platform metadata, fixes dependency paths and compiles missing Mac API shims against UIKit/iOS frameworks. It requires your profile and identity even when preparing an eventual LiveContainer package.

On an expendable staging output, a starting command is:

```sh
python3 compatibility/jsab-keyboard/tools/convert_app.py \
  "$MAC_APP" /private/tmp/jsab-guide/JSAB.app com.example.jsabcompat \
  --profile /path/to/your/profile.mobileprovision \
  --identity 'Apple Development: Your Name (YOUR_TEAM_ID)' \
  --team YOUR_TEAM_ID --no-controller-replay --no-metal-hud
```

The converter deletes its **output** path before copying. Never point that output at your original game or an app containing the only copy of your work. Stop on unresolved dependencies or startup failures; conversion alone does not include the final audio/control/save integration and JSAB patches.

The final port used a separately built local Steam API implementation from the pinned source listed in `THIRD-PARTY.md` for its Steam-facing save interfaces. This repository does not package it or automate installation. `SaveBackend.m` only selects a writable directory; it does not itself implement those interfaces. An original purchase that requires a client/license check is outside this repository's conversion scope.

The original converter output, resolved runtime dependencies and generated shim set were preserved privately in the completed archive. Recreating that exact starting point from an original purchase needs an independently tested dependency-preparation workflow; it is a remaining reproducibility task.

## 3. Rebuild an existing private converted app

Unpack your own archive into an expendable `/private/tmp` directory. For an IPA:

```sh
mkdir -p /private/tmp/jsab-guide
unzip /path/to/your/private/JSAB.ipa -d /private/tmp/jsab-guide
```

Keep the original IPA and baseline engine untouched. Read the runner before using it. Configure explicit paths:

```sh
export JSB_SOURCE_ROOT="$PWD"
export JSB_BUILD_ROOT='/path/to/private/BuildInputs'
export JSB_BASE_UNITY="$JSB_BUILD_ROOT/baseUnityPlayer.dylib"
export JSB_APP='/private/tmp/jsab-guide/Payload/JSAB.app'
export JSB_IDENTITY='Apple Development: Your Name (YOUR_TEAM_ID)'
export JSB_SKIP_DEVICE=1
export JSB_VSYNC_GUARD=1
export JSB_LC_SYSTEM_HEAP=1
bash compatibility/standalone/test_audio.sh
```

`JSB_LC_SYSTEM_HEAP=1` selects the verified LiveContainer allocator fix; the default is 0. The runner restores the baseline Unity library before patching so repeated builds do not patch an already modified copy. Both scripts reject paths outside `/private/tmp` and require the inspected instruction patterns. If a guard fails, stop; do not remove it or transplant offsets.

The runner compiles AppKit/controls/local save configuration, CoreGraphics, CoreVideo and the audio adapters, updates Unity's audio dependencies, applies selected engine fixes and signs the affected libraries/app. It assumes the rest of the converted app, generated shim inputs and dependencies are already present.

Before signing, use your own matching entitlements in `JSB_BUILD_ROOT/entitlements.plist`, and replace the staged app's provisioning profile with your current one if making a signed build. A profile from another developer/device is not reusable.

Set/retain these app plist settings for revision 3:

- `CFBundleShortVersionString`: `1.6.50`; `CFBundleVersion`: `3`.
- `JSBFrameRateOptions`: true; `CADisableMinimumFrameDurationOnPhone`: true.
- Landscape orientations (`UIInterfaceOrientationLandscapeLeft`, `UIInterfaceOrientationLandscapeRight`) for iPhone/iPad.
- Original icon derived locally from the game, with the matching iOS icon entries. Icon images are game assets and excluded here.

For signed deployment, verify all nested code and sign all changed binaries before the app, using entitlements appropriate to each component. The rebuild runner signs only its affected components and the app; it does not renew every pre-existing nested signature. The original port used a development-signed variant; that does not establish perpetual install validity.

## 4. Package for LiveContainer

Create a **separate copy** of the staged app under a separate `Payload/JSAB.app`. For the unsigned variant, remove embedded provisioning profiles, `_CodeSignature` directories and Mach-O signatures in that copy only. Walk Mach-O files by magic/header rather than assuming every executable file is code; scripts/assets must not be treated as Mach-O.

The final archive's unsigned variant was tested in LiveContainer. Importing an unsigned IPA directly as a normal iOS app is not supported. Package the directory named `Payload`, not just the `.app`:

```sh
# Run after preparing the unsigned copy under /private/tmp/jsab-unsigned/Payload.
ditto -c -k --keepParent /private/tmp/jsab-unsigned/Payload /private/tmp/JSAB-LiveContainer.ipa
```

Use the official LiveContainer project for current installation/import instructions. Choose its supported JIT-disabled execution path and import your local IPA. Never distribute the generated IPA or game content.

## 5. Verify on the device

Follow `VERIFY.md`. A successful compile/signature check does not establish gameplay, audio, saves or compatibility. This repository's edited portable runner has been checked for syntax but has not been used to independently reproduce the complete final game build on a fresh device.
