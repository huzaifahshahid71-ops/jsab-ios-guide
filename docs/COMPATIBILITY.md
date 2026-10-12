# Compatibility notes

## Unity allocation under LiveContainer

Startup aborted during IL2CPP initialization in a C++ string growth/free path. Late `dyld_dynamic_interpose` attempts failed to resolve the mismatch, including an attempt targeted at the caller library. API availability or a completed interposition request was not evidence of effective rebinding.

The accepted fix redirects eight paired Unity C++ new/new[]/delete/delete[] entries, including nothrow variants, to the guest binary's existing malloc/free import stubs. `patch_lc_allocator.py` checks thin ARM64 Mach-O, file-backed segments, exact 16-byte function entry patterns, unambiguous stubs, branch alignment/range and decoded targets. It records before/after hashes in a JSON sidecar.

Limitation: throwing new becomes malloc-style on allocation failure; this is not a fully conforming C++ out-of-memory replacement. This patch is for the inspected engine, not a generic Unity solution.

## VSync disabled frame-wait freeze

The reproduced failure froze rendering with audio continuing. The main thread waited on a semaphore while the rendering worker was idle; display callbacks continued.

The inspected engine already stores `(vSyncCount > 0)` at VM `0x17810fc`. `patch_vsync_wait.py` replaces a branch at `0xd0dac0`, using verified executable header padding at `0x3da0`. It preserves the original wait at `0xd0db54` when VSync is enabled and resumes at `0xd0dac4` when disabled. It checks callback instruction patterns, original branch, available padding, load-command bounds and all four counter/VSync control-flow cases.

These addresses are specific to the inspected JSAB 1.6.50 Unity library. Never use them for Silksong or a different engine build.

## Audio

The desktop audio path initially enumerated no usable drivers. `AudioCompat.m` models one stereo output and maps Mac output components to iOS RemoteIO. The format queries supply the AVAudioSession sample rate when RemoteIO reports zero before initialization. The zero-rate path had caused FMOD resampler protection faults. `AudioOutput.c` supplies the expected output forwarding path.

The accepted game produced audio. That does not establish every route-change, interruption or background scenario.

## Input and controls

The overlay emits the keyboard events verified with the Mac game's input path: WASD/arrow movement, Space dash, Return accept and Escape back. Controller and touch held-state sets are tracked separately so releasing the stick does not incorrectly release a concurrently held button. Movement uses a digital radial dead zone and hysteresis.

PS5 Cross maps to dash/accept, Circle to back, Options to pause/menu, Triangle to game options. The overlay supports touch/external controller visibility, right/left/compact layouts and a manual gameplay layout. A native analog experiment did not move the character and was excluded from the accepted build.

## Frame rate and saves

The 60/120 option retargets display timing; Metal presented callbacks count actual presented frames rather than merely drawable requests. Measurements reached 119–120 FPS, with lower samples under load. Host timestamps remain monotonic real time. Game-level rhythm timing remains a separate verification question.

`SaveBackend.m` configures `XDG_DATA_HOME` under `Documents/JSABLocal`; it does not change HOME. The archived implementation's local Steam-facing save path is `Documents/JSABLocal/GSE Saves/531510/remote`. A diagnostic probe can check write/read across launches, but the accepted saved progress/settings also relied on user verification. Normal installation and LiveContainer use separate containers; an IPA does not back up progress.
