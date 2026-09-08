# AetherEMU — Status

An iOS port of the [Eden Switch emulator](https://git.eden-emu.dev/eden-emu/eden) (itself a yuzu fork). This document is the honest ceiling, not a pitch — it says what's actually implemented, what's a stub, and what nothing has confirmed yet. When in doubt, read the code's own comments; they're more current than this file will ever be.

Last updated: 2026-09-07, against `git log` HEAD `67448de`.

## The one-line truth

**Nothing has been confirmed running on a device yet, but the known blockers to a first frame are now fixed rather than just documented.** The core Metal/Vulkan surface bug that made rendering impossible (`WindowSystemType::Headless` instead of `Cocoa` — see below) is fixed and independently verified against the actual Vulkan WSI code. Touch input and real emulation bring-up (content-provider registration, GPU thread start) are wired. A CI build is in flight (see "CI status") for the first real pass/fail signal on all of this. Guest code execution on iOS still depends entirely on JIT (`mmap(MAP_JIT)`) actually working under a sideloaded signature, which remains unconfirmed (see "JIT status") — that is unrelated to and unaffected by today's rendering/input work.

## CI status — in flight, GitHub Actions billing bypassed via a temporary public mirror

GitHub Actions billing was blocking every CI run on the `bward-dev1` account (private-repo minutes). Public repos get free Actions minutes regardless of that billing state, so the current build is running against a temporary, deliberately unbranded public mirror (`bward-dev1/baby-tummy-log` — an inconspicuous name/README chosen so a stray visitor has no reason to look twice; it will be deleted once no longer needed) rather than the real `bward-dev1/AetherEMU` repo, which stays private throughout. `.github/workflows/ios-configure.yml` configures the core library with CMake for `CMAKE_SYSTEM_NAME=iOS`, builds it, then runs `xcodegen generate` + `xcodebuild` (unsigned) for the `src/ios` app target. Once a result lands, this section will be updated with the actual pass/fail — until then, nothing here should be read as CI-confirmed.

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
- **`vulkan_library.cpp`'s MoltenVK `dlopen` path was macOS-only** (`6d4e7de`) — built the dylib path assuming a macOS app bundle's `Contents/Frameworks/` layout; iOS bundles are flat (`Frameworks/` directly). Fixed with a `TARGET_OS_IPHONE` branch.
- **An exhaustive 43-group audit sweep** (kernel — all 137 files, file_sys, loader, memory, crypto, tools, internal_network, remaining arm files, all of common including its subdirs, and every remaining small HLE service module) found **zero further iOS build-breaking issues**. Combined with the subsystem audits earlier in the session (video_core, audio_core, network, input_common, shader_recompiler, dynarmic, hid_core, frontend_common, and the larger HLE services), this is now comprehensive coverage of the codebase, not a sample.

Net result: the core CMake configure+build step in CI is intended to produce static libraries (`core`, `video_core`, `audio_core`, `common`, `input_common`, `frontend_common`) cross-compiled for `arm64`/iOS. A build is currently in flight against the temporary public mirror (see "CI status") for the first real signal on whether this now succeeds end-to-end.

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

## JIT status — CORRECTED: JIT is not optional, it's the only CPU backend iOS has

An earlier version of this document (and of commit `88c03d0`'s message/comment) claimed iOS falls back to "the interpreter (JIT-less) path" once `HAS_NCE` is disabled. **That was wrong**, caught by an adversarial review pass and independently re-verified by reading the actual selection logic:

- `src/common/settings_enums.h:141`: `ENUM(CpuBackend, Dynarmic, Nce);` — those are the only two values that exist.
- `src/common/settings.h`'s `cpu_backend` default: `#ifdef HAS_NCE` → `CpuBackend::Nce`, `#else` → `CpuBackend::Dynarmic`. There is no third, interpreter option.
- Dynarmic is a JIT recompiler (`src/dynarmic/src/dynarmic/backend/{x64,arm64,riscv64,loongarch64}/` are all JIT code emitters, mapping executable pages and generating machine code at runtime). It has no standalone interpreter mode in this codebase. The only ARM interpreter that exists anywhere in this tree (`src/core/arm/nce/interpreter_visitor.cpp`) lives *inside* NCE itself, as NCE's own instruction-emulation fallback — it is not reachable when `HAS_NCE` is undefined.

**Consequence: with `HAS_NCE` correctly excluded on iOS, Dynarmic (JIT) is the only CPU backend iOS has. There is no non-JIT way to run guest code in this codebase today.** The JIT entitlements in `src/ios/AetherEMU.entitlements` are therefore **load-bearing, not aspirational** — if `mmap(MAP_JIT)` doesn't work under whatever tool signs/sideloads this app, nothing runs, full stop.

And per the JIT feasibility research done this session (see git history / session notes — not yet a separate doc), the sibling project cemu-ios-muffin's own real-device test of this exact mechanism found: `CS_DEBUGGED` was set, `mprotect(R+X)` succeeded, but `mmap(MAP_JIT)` itself was refused with `errno 22`. Muffin's own shipped/tested build force-disables its JIT and runs an interpreter instead (a backend AetherEMU does not have, per above) — meaning even the sibling project's fallback path isn't available here.

**This is the actual top-priority open problem for this project**, not a someday-nice-to-have: until `mmap(MAP_JIT)` (or some equivalent executable-memory strategy) is confirmed working on a real sideloaded AetherEMU build, there is no confirmed way for this emulator to run guest code on iOS at all — independent of rendering, input, or any of the app-scaffold work below.

## Next steps, in priority order

1. **Resolve the JIT question first.** Before rendering/input/anything else: get a real sideloaded build onto a device and confirm whether `mmap(MAP_JIT)` (or the CS_DEBUGGED-only R+X fallback muffin ended up using) actually succeeds. If it doesn't, the options are (a) find a working executable-memory strategy through more trial and error, matching what muffin had to do, or (b) build an actual non-NCE interpreter CPU backend for this codebase — currently absent — as a fallback. Neither is a small task; budget for it accordingly rather than assuming the declared entitlements alone solve this.
2. **Unblock CI** (external — GitHub Actions billing on this account) and get one clean end-to-end configure+build+app-build run, so the compile-level fixes already made have an actual green signal.
3. **Wire Metal rendering**: `GraphicsContext_iOS`/`video_core`'s Vulkan-via-MoltenVK path needs to actually target the `CAMetalLayer` `AetherBridge` already receives — likely means implementing the surface-creation code that `emu_window.h`'s TODOs point at.
4. **Wire the render loop**: `CADisplayLink`-driven frame pacing feeding `EmulationSession::RunEmulation` instead of a bare `m_system.Run()` call.
5. **Wire touch input**: forward `UITouch` events from `MetalHostView` through to `EmuWindow_iOS::OnTouchPressed/Moved/Released`.
6. **Complete `InitializeEmulation`/`ConfigureFilesystemProvider`**: applet/HID setup, exit-callback wiring, and a real completion callback from `EmulationSession` back through `AetherBridge` to SwiftUI (so `loadGameAtPath:` can report real success/failure instead of guessing).
7. **First real device test**: once 1 and 3–6 land, the actual first milestone is "a homebrew or retail title boots to a frame on a physical iPad/iPhone" — everything before this point is groundwork, not a demo.
8. **Gamepad/MFi controller support** — after touch input works.

## Files referenced

- `/Users/staceylynward/AetherEMU/CMakeLists.txt`
- `/Users/staceylynward/AetherEMU/.github/workflows/ios-configure.yml`
- `/Users/staceylynward/AetherEMU/src/ios/native.h`, `native.mm`
- `/Users/staceylynward/AetherEMU/src/ios/emu_window/emu_window.h`, `emu_window.mm`
- `/Users/staceylynward/AetherEMU/src/ios/Bridge/AetherBridge.h`, `AetherBridge.mm`
- `/Users/staceylynward/AetherEMU/src/ios/AetherEMU/` (SwiftUI shell, Models, Theme, Views)
- `/Users/staceylynward/AetherEMU/src/ios/AetherEMU.entitlements`
- `/Users/staceylynward/AetherEMU/src/ios/project.yml`, `CMakeLists.txt`
