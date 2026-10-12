# Just Shapes & Beats on iPhone

A practical guide and compatibility-source snapshot for the JSAB **1.6.50 / port revision 3** experiment. The final build was user-verified on an **iPhone 15 Pro, iOS 27.0.1, in LiveContainer with JIT disabled** on 12 October 2026. Build host: Apple Silicon M5 Mac, Xcode 27.0, iPhoneOS 27.0 SDK.

This repository contains the UIKit controls, audio compatibility layer, Mac-to-iOS conversion helpers and guarded JSAB engine patch scripts. **Bring your own game.** There are no game binaries/assets, IPAs, saves, Apple SDKs, certificates or provisioning profiles here. It is unofficial and not affiliated with Berzerk Studio, Apple or LiveContainer.

## What worked

- Graphics, sound, touch movement/DASH/menu buttons, and saved progress after restart.
- PS5 Bluetooth controller: stick/D-pad movement, Cross dash/accept, Circle back, Options pause/menu, Triangle game options.
- Landscape orientation, original icon, Options panel and persistent settings.
- Optional 60/120 FPS selection. Presented-frame measurements reached 119–120; performance varies with load and device policy.
- VSync can be toggled without the previous frame-wait freeze.

Movement is a digital keyboard bridge with dead zone/hysteresis, not true analog movement. The picture remains fitted at 16:9. High refresh is not a guarantee of sustained 120 FPS or an independent verification of rhythm/simulation timing. Other devices, OS versions and game updates are unverified.

## Start here

1. Read [the build guide](docs/BUILD-GUIDE.md) for input requirements, conversion and rebuilding.
2. Read [why the compatibility fixes were needed](docs/COMPATIBILITY.md) before using the patches.
3. Use [the verification checklist](docs/VERIFY.md) after building and importing.
4. See [source provenance and licenses](THIRD-PARTY.md).

**Reproducibility status:** this is a documented, verified-port source snapshot. The archive-based rebuild path uses privately retained converted game/build inputs. A fully automated, independently reproduced clean build from an original Mac purchase is not yet provided. The guide identifies the missing preparation steps instead of presenting a one-command promise.

## Repository contents

| Path | Purpose |
|---|---|
| `compatibility/jsab-keyboard/tools/` | Mach-O inspection, symbol-gap analysis, conversion and device diagnostic helpers |
| `compatibility/jsab-keyboard/shim/overrides/` | UIKit-backed AppKit, display, Metal and Mac API adapters |
| `compatibility/standalone/TouchControls.m` | Touch overlay, PS5 controller bridge, Options and FPS controls |
| `compatibility/standalone/AudioCompat.m`, `AudioOutput.c` | CoreAudio/RemoteIO compatibility |
| `compatibility/standalone/SaveBackend.m` | Writable local save directory, optional diagnostic probe |
| `compatibility/standalone/patch_*.py` | Guarded fixes for the inspected JSAB Unity library only |
| `compatibility/standalone/test_audio.sh` | Portable archive-input rebuild runner; defaults to no device install |
| `scripts/check-public-content.py` | Checks tracked/staged files for private or binary inputs |

## Scope

Use a legally obtained copy on your own device. This project does not supply or implement DRM, anti-tamper, license or store-client check bypasses. If your game needs an unavailable service or fails a license check, stop and resolve it through supported means. The separately developed local Steam-facing save integration is documented as an external dependency; no emulator is vendored here.

These sources are useful references for other games, not automatic compatibility. In particular, the Silksong desktop Mono builds and Android IL2CPP build are different engines/platforms; do not carry JSAB patch offsets, Steam integration or save backend into Silksong.

## License

MIT; preserve the upstream Ross Fisher notice in [LICENSE](LICENSE). This repository's compatibility additions and documentation are provided under the same license. External dependencies retain their own licenses, including LGPL obligations where applicable. Game and Apple code are excluded.
