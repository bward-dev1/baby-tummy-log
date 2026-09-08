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

    const EmuWindow_iOS& Window() const;
    EmuWindow_iOS& Window();

    // TODO(ios): Real signature/ownership TBD once the bridge knows what a "native
    // surface" is on this platform (see AetherNativeSurface in emu_window.h) -- likely a
    // CAMetalLayer* handed down from a SwiftUI/UIKit MTKView-equivalent.
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
    std::atomic<bool> m_is_running = false;
    std::atomic<bool> m_is_paused = false;
    std::unique_ptr<FileSys::ManualContentProvider> m_manual_provider;

    // GPU driver parameters
    std::shared_ptr<Common::DynamicLibrary> m_vulkan_library;

    // Synchronization
    std::condition_variable_any m_cv;
    mutable std::mutex m_mutex;
};
