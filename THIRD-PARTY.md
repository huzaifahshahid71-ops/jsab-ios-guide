# Source provenance and resources

## Included compatibility sources

The converter and Mac API shim foundation originated from [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public), MIT, Copyright (c) 2026 Ross Fisher. The original license is retained at the repository root and in `compatibility/jsab-keyboard/LICENSE`. This snapshot includes local JSAB-specific modifications; no exact upstream base commit has been asserted because it was not captured in this snapshot's provenance.

The touch/controller overlay, audio compatibility additions, local save directory configuration and guarded allocator/frame-wait fixes came from the completed local JSAB project. This repository provides those additions/documentation under MIT alongside the preserved upstream notice. Archived runners and historical checkpoints contained device identifiers, local paths and superseded experiments; the public snapshot omits historical logs and makes the runner's personal inputs explicit environment variables.

## External dependencies (not vendored)

- [squareloopthings/goldberg-mac](https://github.com/squareloopthings/goldberg-mac), archived outer commit `6aab9c6ff879ceae24891b7930a222829573bddf`. The project's preserved provenance records vendored [Detanup01/gbe_fork](https://github.com/Detanup01/gbe_fork) commit `e4035e085a028a195c2e3f13e3207e0dfdadce57` and dependency-source commit `92a4a130262083c4e887155cbe6bcab99baf36ea`. Its emulator has LGPL-3.0-or-later licensing and third-party notices. Consult that project's build instructions and license; this repository does not relicense, vendor or distribute its binary/source archives.
- [LiveContainer official project](https://github.com/LiveContainer/LiveContainer): current installation, import and JIT-disabled execution instructions. Device provisioning/host requirements must be checked with the project; the accepted JSAB test is not a claim of universal support.
- [Apple Xcode](https://developer.apple.com/xcode/): compiler, SDK, signing and device tooling. Obtain from Apple; no Apple code is included.

The upstream converter's policy excludes DRM, anti-tamper, license and store-client check workarounds. The separately archived JSAB local save integration is not presented as part of that upstream project's supported scope.

## Excluded material

Game assets/binaries/icons, original packages, signed/unsigned IPAs, baseline UnityPlayer, generated runtime libraries, saved games, raw diagnostic logs/crash reports, source archive bundles, private signing material and machine-specific provisioning entitlements. Build these or obtain them from your own authorized private inputs. The private local archive remains separate from this Git repository.
