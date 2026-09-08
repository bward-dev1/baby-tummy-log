// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <optional>

#include "core/core.h"
#include "core/file_sys/registered_cache.h"
#include "core/perf_stats.h"
#include "frontend_common/content_manager.h"
#include "ios/emu_window/emu_window.h"
#include "video_core/rasterizer_interface.h"

// TODO(ios): This mirrors Android's `EmulationSession` (src/android/app/src/main/jni/native.h)
// -- a process-wide singleton owning the Core::System instance and the current
// EmuWindow. On Android, JNI calls from Kotlin drive this; on iOS the equivalent
// callers will be Swift/ObjC via the .mm bridge methods below, once an app target
// exists to call them. Everything here is a stub: enough surface area to compile and
// link against the core libraries, not a working emulation session.
class EmulationSession final {
public:
    explicit EmulationSession();
    ~EmulationSession() = default;

    static EmulationSession& GetInstance();
    const Core::System& System() const;
    Core::System& System();
    InputCommon::InputSubsystem& GetInputSubsystem();

    // NOTE(ios): neither accessor takes m_mutex -- an adversarial review pass flagged
    // that callers doing `if (!IsRunning()) return; ... Window()...` as two separate
    // unlocked steps (AetherBridge.mm's touch forwarding does exactly this) can race
    // ShutdownEmulation()'s locked m_window.reset(). Currently unreachable: nothing
    // calls ShutdownEmulation anywhere in this tree yet. The moment a real teardown path
    // exists, either these accessors or their call sites need to take m_mutex too (see
    // SurfaceChanged() below for the pattern already fixed this way).
    const EmuWindow_iOS& Window() const;
    EmuWindow_iOS& Window();

    // AetherNativeSurface is only forward-declared here (stays ObjC-free); its real
    // definition (a CAMetalLayer* handed down from MetalHostView, see MetalView.swift)
    // lives in ios/native_surface.h, along with the ARC-strong-ref lifetime notes.
    void SetNativeSurface(AetherNativeSurface* native_surface);
    void SurfaceChanged();

    bool IsRunning() const;
    bool IsPaused() const;
    void PauseEmulation();
    void UnPauseEmulation();
    void HaltEmulation();
    void RunEmulation();
    void ShutdownEmulation();

    const Core::PerfStatsResults& PerfStats();

    // TODO(ios): filepath handling should go through NSURL / security-scoped bookmarks
    // (iOS sandboxing) rather than a raw path once there's a real file picker to wire
    // this up to.
    void ConfigureFilesystemProvider(const std::string& filepath);

    // TODO(ios): mirrors Android's InitializeSystem(bool reload) minus the one-time
    // logging/input-subsystem bring-up (native.mm's constructor + EmulationSession
    // lifetime already cover that on this platform) -- wires m_vfs into Core, constructs
    // m_manual_provider, and registers the content-provider union. Must run before
    // ConfigureFilesystemProvider/InitializeEmulation touch either of those.
    void InitializeSystem();

    Core::SystemResultStatus InitializeEmulation(const std::string& filepath);

    static void OnEmulationStarted();

private:
    static void OnEmulationStopped(Core::SystemResultStatus result);

private:
    // Window management
    std::unique_ptr<EmuWindow_iOS> m_window;
    AetherNativeSurface* m_native_surface{};

    // Core emulation
    Core::System m_system;
    InputCommon::InputSubsystem m_input_subsystem;
    Core::PerfStatsResults m_perf_stats{};
    std::shared_ptr<FileSys::VfsFilesystem> m_vfs;
    Core::SystemResultStatus m_load_result{Core::SystemResultStatus::ErrorNotInitialized};
    // Guards the one-time Core::System::Initialize() call in InitializeSystem() below --
    // mirrors Android's `if (!reload) System().Initialize();` in its JNI initializeSystem
    // wrapper (there is no iOS reload/relaunch flow yet, so this is just "has this
    // process-wide singleton done its one-time Core bring-up" rather than a real
    // reload-vs-first-launch distinction).
    bool m_system_initialized{false};
    std::atomic<bool> m_is_running = false;
    std::atomic<bool> m_is_paused = false;
    std::unique_ptr<FileSys::ManualContentProvider> m_manual_provider;

    // GPU driver parameters
    std::shared_ptr<Common::DynamicLibrary> m_vulkan_library;

    // Synchronization
    std::condition_variable_any m_cv;
    mutable std::mutex m_mutex;
};
