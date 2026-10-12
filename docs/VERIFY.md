# Device verification

Use a separate staging copy and preserve the device's existing save container.

- Confirm game version, engine and ARM64 architecture match the documented inputs; record hashes of private baseline and patched binaries.
- Confirm patch guards pass and preserve JSON sidecars privately. Verify affected nested signatures for a signed install.
- Launch through LiveContainer with JIT disabled. Confirm the title screen renders without allocator aborts.
- Play a level: move, DASH, accept/back, pause, open game options; exercise stick and button simultaneously.
- Confirm sound, restart and confirm actual saved progress/settings persist.
- Connect a PS5 Bluetooth controller; check each documented mapping and overlay visibility.
- Test landscape, icon, Options placement, layout selection, hidden-panel reopening and FPS visibility.
- Toggle VSync off and on during gameplay. Check that rendering and controls continue.
- Select 60, then 120 on supported hardware. Use presented-frame measurements; do not claim performance from the target setting alone.
- Check rhythm/simulation timing independently if reporting that high refresh preserves game timing.

A new game, Unity build, phone or OS version needs its own validation. No phone installation or gameplay test was performed during preparation of this public guide; acceptance refers to the archived revision-3 port.
