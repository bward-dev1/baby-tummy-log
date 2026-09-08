// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#include "ios/native.h"

#include "common/logging.h"
#include "common/settings.h"
#include "core/file_sys/vfs/vfs_real.h"
#include "core/hle/service/am/applet_manager.h"

namespace {
EmulationSession s_instance;
}

EmulationSession::EmulationSession() {
    m_vfs = std::make_shared<FileSys::RealVfsFilesystem>();
}

EmulationSession& EmulationSession::GetInstance() {
    return s_instance;
}

const Core::System& EmulationSession::System() const {
    return m_system;
}

Core::System& EmulationSession::System() {
    return m_system;
}

InputCommon::InputSubsystem& EmulationSession::GetInputSubsystem() {
    return m_input_subsystem;
}

const EmuWindow_iOS& EmulationSession::Window() const {
    return *m_window;
}

EmuWindow_iOS& EmulationSession::Window() {
    return *m_window;
}

void EmulationSession::SetNativeSurface(AetherNativeSurface* native_surface) {
    m_native_surface = native_surface;
}

void EmulationSession::SurfaceChanged() {
    if (!IsRunning()) {
        return;
    }
    m_window->OnSurfaceChanged(m_native_surface);
}

bool EmulationSession::IsRunning() const {
    return m_is_running;
}

bool EmulationSession::IsPaused() const {
    return m_is_running && m_is_paused;
}

const Core::PerfStatsResults& EmulationSession::PerfStats() {
    m_perf_stats = m_system.GetAndResetPerfStats();
    return m_perf_stats;
}

void EmulationSession::ConfigureFilesystemProvider(const std::string& filepath) {
    // TODO(ios): Mirrors EmulationSession::ConfigureFilesystemProvider on Android, minus
    // the ManualContentProvider container-entry scan -- needs a real pass once there's a
    // game/file picker on this platform to feed it a path (likely via a security-scoped
    // NSURL bookmark rather than a raw filesystem path).
    const auto file = m_system.GetFilesystem()->OpenFile(filepath, FileSys::OpenMode::Read);
    if (!file) {
        LOG_ERROR(Frontend, "Failed to open file for filesystem provider: {}", filepath);
    }
}

Core::SystemResultStatus EmulationSession::InitializeEmulation(const std::string& filepath) {
    std::scoped_lock lock(m_mutex);

    // TODO(ios): Real implementation needs to mirror Android's InitializeEmulation --
    // software keyboard/applet setup, HID device reload, program-select/exit callbacks,
    // etc. This stub only stands up the window and attempts a core load so the bridge
    // has a real (if incomplete) call path to build against.
    m_window = std::make_unique<EmuWindow_iOS>(m_native_surface, m_vulkan_library);

    m_system.SetShuttingDown(false);
    m_system.ApplySettings();
    Settings::LogSettings();

    // TODO(ios): applet_id/launch_type/program_index should come from real frontend
    // state (which title is being launched, whether it's a sub-program relaunch) once
    // there's an app UI driving this -- Android's equivalent builds this from JNI call
    // arguments. Defaults here are enough to make the call shape compile/link.
    Service::AM::FrontendAppletParameters params{};
    m_load_result = m_system.Load(*m_window, filepath, params);
    if (m_load_result != Core::SystemResultStatus::Success) {
        return m_load_result;
    }

    m_system.RegisterExitCallback([&] { HaltEmulation(); });

    OnEmulationStarted();
    return Core::SystemResultStatus::Success;
}

void EmulationSession::ShutdownEmulation() {
    std::scoped_lock lock(m_mutex);
    m_is_running = false;

    // TODO(ios): mirror Android's fuller teardown -- unload input devices (HIDCore),
    // re-enable all controller style tags, detach debugger, program-relaunch handling.
    // Left minimal until there's a real caller.
    if (m_load_result == Core::SystemResultStatus::Success) {
        m_system.ShutdownMainProcess();
        m_load_result = Core::SystemResultStatus::ErrorNotInitialized;
    }
    m_window.reset();

    OnEmulationStopped(m_load_result);
}

void EmulationSession::PauseEmulation() {
    std::scoped_lock lock(m_mutex);
    m_system.Pause();
    m_is_paused = true;
}

void EmulationSession::UnPauseEmulation() {
    std::scoped_lock lock(m_mutex);
    m_system.Run();
    m_is_paused = false;
}

void EmulationSession::HaltEmulation() {
    std::scoped_lock lock(m_mutex);
    m_is_running = false;
    m_cv.notify_one();
}

void EmulationSession::RunEmulation() {
    {
        std::scoped_lock lock(m_mutex);
        m_is_running = true;
    }

    // TODO(ios): mirror Android's disk shader cache preload + m_system.Run() loop once
    // there's a real render loop (CADisplayLink-driven) to drive frames from.
    void(m_system.Run());
}

// TODO(ios): Android notifies the Kotlin frontend via a JNI static-method callback here.
// There's no JNI on this platform -- the equivalent will be a C function pointer /
// block callback registered by the Swift/ObjC app layer, or a delegate protocol, once
// that app layer exists.
void EmulationSession::OnEmulationStarted() {
    LOG_INFO(Frontend, "EmulationSession::OnEmulationStarted (stub, no frontend callback wired)");
}

void EmulationSession::OnEmulationStopped(Core::SystemResultStatus result) {
    LOG_INFO(Frontend, "EmulationSession::OnEmulationStopped (stub, no frontend callback wired): {}",
              static_cast<int>(result));
}
