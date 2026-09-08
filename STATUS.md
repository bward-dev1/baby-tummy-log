# AetherEMU — Status

An iOS port of the [Eden Switch emulator](https://git.eden-emu.dev/eden-emu/eden) (itself a yuzu fork). This document is the honest ceiling, not a pitch — it says what's actually implemented, what's a stub, and what nothing has confirmed yet. When in doubt, read the code's own comments; they're more current than this file will ever be.

Last updated: 2026-09-07, against `git log` HEAD `40ada1c` (40 commits since the initial snapshot).

## The one-line truth

**Nothing has run on a device or in a simulator.** The core library and the app-target scaffold both build far enough to be interesting, but CI has never finished an end-to-end build (see "CI status" below), and even if it had, the app does not yet draw a frame, take touch input, or load a game. This is a pre-alpha port: real engineering progress on the hard cross-compilation problems, zero playable behavior.

## CI status — currently blocked, not currently green

`.github/workflows/ios-configure.yml` configures the core library with CMake for `CMAKE_SYSTEM_NAME=iOS`, builds it, then runs `xcodegen generate` + `xcodebuild` (unsigned) for the `src/ios` app target. **GitHub Actions billing is currently blocking all CI runs on this account.** This is an external account/billing problem, not a code problem — it means the workflow above has not produced a fresh pass/fail signal recently, and nothing in this document about "builds" should be read as "CI says so." Every claim below is grounded in reading the source and CMake logic directly, not in a green checkmark.

## Core library (Eden/yuzu C++ core) — iOS build fixes so far

These are real, specific fixes to get the shared C++ core (`common`, `core`, `video_core`, `audio_core`, `input_common`, `frontend_common`) to configure and compile for `CMAKE_SYSTEM_NAME=iOS`, found by walking `git log` and the top-level `CMakeLists.txt`:

- **`HAS_NCE` reverted off for iOS** (`88c03d0`) — an earlier pass had turned this on for iOS by omission; it's Linux-specific (ARM64 ucontext/TLS layout), and the top-level `CMakeLists.txt` now has an explicit comment explaining why omitting `IOS` from that guard is *correct*, not an oversight. Net effect: the interpreter (JIT-less) path is what the core actually falls back to on iOS, unconditionally.
- **Boost::process excluded on iOS** (`36f9e42`, `88308ea`) — `boost::process` was in `BOOST_INCLUDE_LIBRARIES` unconditionally and doesn't build/link for iOS; it's now stripped from the list under `if (IOS)`.
- **`ENABLE_LIBUSB` forced off for iOS**, at both the CI flag level and the CMakeLists.txt level (`f0c08c8`, `e290f03`) — libusb has no iOS backend; the option now can't accidentally default on for iOS the way `cmake_dependent_option(... "WIN32 OR LINUX OR FREEBSD OR APPLE" ...)` would otherwise allow.
- **`YUZU_ROOM` / `YUZU_ROOM_STANDALONE` disabled on iOS** (`cmake_dependent_option(... "NOT ANDROID AND NOT IOS" ...)`) and **`YUZU_CMD`** likewise — these are desktop-networking/CLI features with no iOS story yet.
- **dynarmic's exception handler forced to the generic backend on iOS** (`34fb281`) — macOS's `elseif (APPLE)` branch (MIG-based Mach exception ports) was unguarded and would have silently applied to iOS too; added an explicit `elseif (IOS)` branch ahead of it so iOS gets `exception_handler_generic.cpp` instead.
- **`<sys/random.h>` guarded to macOS only** in `host_memory.cpp` (`6d38bd6`) — header doesn't exist on iOS.
- **`TARGET_OS_MAC` fix** — that macro is true for *every* Apple platform including iOS, so code gated on it that assumed "macOS, therefore IOKit is available" was wrong on iOS; fixed to check the right condition (`bd87e10`).
- **cubeb's AudioUnit backend disabled on iOS** (`7f84af4`) — desktop-audio backend not applicable.
- **MoltenVK library path fix** (`833fb20`) — the vendored/CPM MoltenVK package nests an extra `MoltenVK/` directory level that the original path assumed away.
- **`SignalPipe` missing the `error_code` `write_some` overload** (`9f5f792`) — a real compile error, not a platform-gating issue; fixed directly.
- Two more unguarded desktop/macOS-only branches excluded from iOS (`34fb281`, second half).

Net result: the core CMake configure+build step in CI is intended to produce static libraries (`core`, `video_core`, `audio_core`, `common`, `input_common`, `frontend_common`) cross-compiled for `arm64`/iOS. Whether that step currently succeeds end-to-end is exactly what's unconfirmed, per the CI-blocked note above — the fixes above were each made in response to specific compile/link errors surfaced by earlier (successful-at-configuring, at minimum) CI runs, so there is real signal that the approach works, just not a recent full-green run.

## App-target scaffold (`src/ios/`) — what exists

- **`AetherEMU.xcodeproj` is generated, not checked in** — `xcodegen generate` reads `project.yml` and produces the project at CI/build time. `project.yml` wires up bundle ID, deployment target (iOS 16.0), the bridging header, and — critically — an `OTHER_LDFLAGS` response file (`link-flags.txt`) generated by `ci/generate-link-flags.sh` that points Xcode at the full paths of the CMake-built static libs, since Xcode compiles the Swift/ObjC++ app target itself rather than through CMake.
- **`aetheremu-ios` static library** (`src/ios/CMakeLists.txt`) links `emu_window.mm` + `native.mm` against the core libraries and `PLATFORM_LIBRARIES` (Metal, UIKit, CoreVideo, CoreMedia, Security, UniformTypeIdentifiers, Foundation) via the top-level `if (IOS)` framework block. This is deliberately a static lib, not a `.framework`/app bundle — there's no code-signing or bundle step at this layer.
- **`EmulationSession`** (`native.h`/`native.mm`) — a process-wide singleton mirroring Android's `EmulationSession` (JNI equivalent). Owns `Core::System`, the input subsystem, and an `EmuWindow_iOS`. Has real method bodies for pause/resume/halt/perf-stats bookkeeping, but its own header says outright: *"Everything here is a stub: enough surface area to compile and link against the core libraries, not a working emulation session."*
- **`EmuWindow_iOS`** (`emu_window/emu_window.h`/`.mm`) — subclasses `Core::Frontend::EmuWindow`. Its own comment: *"currently an unimplemented stub... None of the surface/frame-rate-hint logic below is real yet."* Touch handlers (`OnTouchPressed/Moved/Released`) exist as method signatures with no UIKit wiring behind them.
- **`AetherBridge`** (Objective-C++, `Bridge/AetherBridge.mm`) — the Swift-callable surface over `EmulationSession`. Real, thought-through synchronization (an `os_unfair_lock`-guarded `AetherNativeSurface` struct wrapping a strongly-retained `CAMetalLayer*`, a serial dispatch queue for load/run calls off the main thread). `loadGameAtPath:` dispatches to `ConfigureFilesystemProvider` + `InitializeEmulation` + `RunEmulation` — but see below, those are stubs on the C++ side, and the bridge's own comment admits it "reports optimistically" (always returns success immediately) since there's no completion callback wired yet.
- **SwiftUI shell** (`AetherEMU/`): `AetherEMUApp.swift` (app entry, forces dark mode + hides system overlays), `ContentView.swift` (theme picker → home screen → running-game view state machine, plus a `.fileImporter` for NSP/XCI/NCA with security-scoped resource access), `MetalView.swift` (`MetalHostView`, a bare `CAMetalLayer`-backed `UIView` that attaches/detaches itself to `AetherBridge` on `didMoveToWindow`/`layoutSubviews` — the comment is explicit: *"No CADisplayLink, resize forwarding, or touch input is wired yet."*). `Models/` (`Game`, `GameFolder`, `AppTheme`) and `Theme/Views/` implement two selectable home-screen layouts (Rail and Dock, with Folders support in the Dock theme) — this is real, non-trivial SwiftUI work, but it's presentation-layer only; it has nothing to do with emulation running.

## What is explicitly NOT implemented yet

- **No Metal rendering.** `MetalHostView` exists and hands its `CAMetalLayer` down to `AetherBridge`/`EmulationSession`, but nothing on the C++ side (`GraphicsContext_iOS`, `video_core`) reads that layer to build a `CAMetalDrawable` or issue a single draw call. `AetherBridge.mm`'s own comment says this directly: *"EmuWindow_iOS/GraphicsContext_iOS never dereference it today... when Metal rendering is wired up, whatever reads the layer... will need to move into an .mm file."*
- **No touch or gamepad input.** `EmuWindow_iOS::OnTouchPressed/Moved/Released` are unimplemented signatures with a TODO to wire to UIKit `UITouch` forwarding. There is no gamepad/MFi controller integration at all.
- **No real game loading.** `EmulationSession::InitializeEmulation` in `native.mm` is, per its own comment, a stub: *"This stub only stands up the window and attempts a core load so the bridge has a real (if incomplete) call path to build against."* It's missing software-keyboard/applet setup, HID device reload, and program-select/exit callback wiring that Android's equivalent has. `ConfigureFilesystemProvider` is similarly a stub missing the `ManualContentProvider` container-entry scan. No file has ever actually been loaded through this path on real hardware — it's untested even in principle since nothing draws or accepts input yet.
- **No render loop.** `RunEmulation()` calls `m_system.Run()` directly rather than driving frames from a `CADisplayLink`, per its own TODO.
- **No frontend callback wiring.** `OnEmulationStarted`/`OnEmulationStopped` just log; there's no delegate/block callback back into Swift, so the SwiftUI layer can't currently learn whether a load actually succeeded — `AetherBridge.loadGameAtPath:` returns success unconditionally, before the async load has even attempted anything.

## JIT status

**JIT-less/interpreter is the only claimed-working execution path.** This isn't a gap to fill later so much as the deliberate current default: `HAS_NCE` is left off for iOS in the top-level `CMakeLists.txt` specifically so the interpreter path runs regardless of what the entitlements below claim.

The JIT entitlements in `src/ios/AetherEMU.entitlements` (`com.apple.security.cs.allow-jit`, `com.apple.security.cs.disable-executable-page-protection`, `dynamic-codesigning`, `get-task-allow`) are declared but **unconfirmed** — the file's own comment is the honest statement of the situation and shouldn't be improved on:

> "These declare intent for MAP_JIT; they are not a confirmed way to get JIT working on iOS. `get-task-allow` / `CS_DEBUGGED` (set by sideloading tools like SideStore/AltStore via a momentary debugger attach at launch) is necessary but may not be sufficient on its own for `mmap(MAP_JIT)` to succeed... Whether this does anything depends on how whatever tool signs/re-signs this app handles entitlement injection, which this repo doesn't control... JIT here is aspirational, not load-bearing."

In short: even if JIT somehow worked, the core doesn't currently try to use it on iOS (`HAS_NCE` is off), so the entitlements exist for a future where the CPU-emulation backend is revisited — not for anything active today.

## Next steps, in priority order

1. **Unblock CI** (external — GitHub Actions billing on this account) and get one clean end-to-end configure+build+app-build run, so the fixes above have an actual green signal instead of "should work per reading the code."
2. **Wire Metal rendering**: `GraphicsContext_iOS`/`video_core`'s Vulkan-via-MoltenVK path needs to actually target the `CAMetalLayer` `AetherBridge` already receives — likely means implementing the surface-creation code that `emu_window.h`'s TODOs point at.
3. **Wire the render loop**: `CADisplayLink`-driven frame pacing feeding `EmulationSession::RunEmulation` instead of a bare `m_system.Run()` call.
4. **Wire touch input**: forward `UITouch` events from `MetalHostView` through to `EmuWindow_iOS::OnTouchPressed/Moved/Released`.
5. **Complete `InitializeEmulation`/`ConfigureFilesystemProvider`**: applet/HID setup, exit-callback wiring, and a real completion callback from `EmulationSession` back through `AetherBridge` to SwiftUI (so `loadGameAtPath:` can report real success/failure instead of guessing).
6. **First real device test**: once 2–5 land, the actual first milestone is "a homebrew or retail title boots to a frame on a physical iPad/iPhone via the interpreter path" — everything before this point is groundwork, not a demo.
7. **Gamepad/MFi controller support** — after touch input works, since touch is the more likely primary input method and simpler to wire.
8. **Revisit JIT** only after the interpreter path is proven and if performance demands it — this means confirming whether `mmap(MAP_JIT)` actually succeeds under a sideloaded signature in practice, which nothing in this repo currently tests.

## Files referenced

- `/Users/staceylynward/AetherEMU/CMakeLists.txt`
- `/Users/staceylynward/AetherEMU/.github/workflows/ios-configure.yml`
- `/Users/staceylynward/AetherEMU/src/ios/native.h`, `native.mm`
- `/Users/staceylynward/AetherEMU/src/ios/emu_window/emu_window.h`, `emu_window.mm`
- `/Users/staceylynward/AetherEMU/src/ios/Bridge/AetherBridge.h`, `AetherBridge.mm`
- `/Users/staceylynward/AetherEMU/src/ios/AetherEMU/` (SwiftUI shell, Models, Theme, Views)
- `/Users/staceylynward/AetherEMU/src/ios/AetherEMU.entitlements`
- `/Users/staceylynward/AetherEMU/src/ios/project.yml`, `CMakeLists.txt`
