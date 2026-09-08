// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#include "ios/native.h"

#include <chrono>

#include "common/logging.h"
#include "common/settings.h"
#include "core/file_sys/content_archive.h"
#include "core/file_sys/vfs/vfs_real.h"
#include "core/hle/service/am/applet_manager.h"
#include "core/hle/service/filesystem/filesystem.h"
#include "core/loader/loader.h"

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

void EmulationSession::InitializeSystem() {
    // TODO(ios): Mirrors the non-JNI portion of Android's InitializeSystem(bool reload) --
    // filesystem/content-provider bring-up. Skips Android's `!reload` branch (log-system
    // Common::Log::Initialize/Start + m_input_subsystem.Initialize()): those are one-time
    // process bring-up steps that belong in whatever iOS app-launch path constructs this
    // singleton, not here, and there is no `reload` concept on iOS yet (no re-launch/
    // program-select flow exists). Revisit if iOS grows a reload path that needs to skip
    // re-registering the content provider.
    m_system.SetFilesystem(m_vfs);
    m_system.GetUserChannel().clear();
    m_manual_provider = std::make_unique<FileSys::ManualContentProvider>();
    m_system.SetContentProvider(std::make_unique<FileSys::ContentProviderUnion>());
    m_system.RegisterContentProvider(FileSys::ContentProviderUnionSlot::FrontendManual,
                                      m_manual_provider.get());
    m_system.GetFileSystemController().CreateFactories(*m_vfs);
}

void EmulationSession::ConfigureFilesystemProvider(const std::string& filepath) {
    // TODO(ios): Mirrors EmulationSession::ConfigureFilesystemProvider on Android. Filepath
    // handling should go through NSURL / security-scoped bookmarks (iOS sandboxing) rather
    // than a raw path once there's a real file picker to wire this up to -- untested since
    // there is no such picker yet.
    const auto file = m_system.GetFilesystem()->OpenFile(filepath, FileSys::OpenMode::Read);
    if (!file) {
        LOG_ERROR(Frontend, "Failed to open file for filesystem provider: {}", filepath);
        return;
    }

    if (m_manual_provider->AddEntriesFromContainer(file)) {
        return;
    }

    auto loader = Loader::GetLoader(m_system, file);
    if (!loader) {
        return;
    }

    const auto file_type = loader->GetFileType();
    if (file_type == Loader::FileType::Unknown || file_type == Loader::FileType::Error) {
        return;
    }

    u64 program_id = 0;
    const auto read_result = loader->ReadProgramId(program_id);
    if (read_result == Loader::ResultStatus::Success && file_type == Loader::FileType::NCA) {
        m_manual_provider->AddEntry(FileSys::TitleType::Application,
                                     FileSys::GetCRTypeFromNCAType(FileSys::NCA{file}.GetType()),
                                     program_id, file);
    }
}

Core::SystemResultStatus EmulationSession::InitializeEmulation(const std::string& filepath) {
    std::scoped_lock lock(m_mutex);

    // TODO(ios): Real implementation still needs to mirror Android's software-keyboard/
    // web-browser applet setup and program-select (RegisterExecuteProgramCallback)
    // machinery -- both are blocked on new iOS-side plumbing (see native.h TODOs) and are
    // deliberately left out here rather than guessed at. What follows is the rest of
    // Android's InitializeEmulation: system/content-provider bring-up, filesystem
    // provider config, input-device reload, load, then GPU thread start.
    m_window = std::make_unique<EmuWindow_iOS>(m_native_surface, m_vulkan_library);

    InitializeSystem();

    m_system.SetShuttingDown(false);
    m_system.ApplySettings();
    Settings::LogSettings();
    m_system.HIDCore().ReloadInputDevices();

    // TODO(ios): SetFrontendAppletSet is intentionally NOT called here -- Android's
    // populates the Software Keyboard / Web Browser slots with AndroidKeyboard /
    // AndroidWebBrowser, JNI-backed implementations with no iOS equivalent yet. Leaving
    // every slot unset (rather than fabricating a fake non-null applet) is the honest
    // interim state; it's unverified whether Core has a defined no-applet fallback or
    // whether this will need addressing before any title that invokes an applet can run.

    ConfigureFilesystemProvider(filepath);

    // TODO(ios): applet_id/launch_type/program_index should come from real frontend
    // state (which title is being launched, whether it's a sub-program relaunch) once
    // there's an app UI driving this -- Android's equivalent builds this from JNI call
    // arguments. Defaults here are enough to make the call shape compile/link.
    Service::AM::FrontendAppletParameters params{};
    m_load_result = m_system.Load(*m_window, filepath, params);
    if (m_load_result != Core::SystemResultStatus::Success) {
        return m_load_result;
    }

    m_system.GPU().Start();
    m_system.GetCpuManager().OnGpuReady();
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

    // NOTE(ios): Core::System::Run() is a one-shot unpause -- it flips the kernel/core_timing
    // suspend flags and returns immediately (core/core.cpp, Impl::Run()). It is not a blocking
    // per-frame loop. The actual render loop lives inside video_core's own GPU thread
    // (VideoCommon::GPUThread::ThreadManager, started from GPU::Impl::Start()), which is driven
    // entirely by the emulated guest submitting command lists -- it has no dependency on any
    // per-frame callback from this (or any) frontend. Android's SDL/Qt-equivalent frontends
    // don't drive frames externally either; do not add a CADisplayLink-fed "tick"/"renderFrame"
    // call into EmulationSession, it would just be a redundant, incorrect driver competing with
    // the GPU thread that's already presenting.
    //
    // TODO(ios): Android preloads the disk shader cache here (LoadDiskResources +
    // LoadCallbackStage progress callback) before calling Run() -- skipped for now since it's
    // orthogonal to the render-loop question and untested on this platform; add it once there's
    // a frontend progress UI to wire the callback into.
    void(m_system.Run());

    // TODO(ios): Android also calls m_system.InitializeDebugger() here when
    // m_system.DebuggerEnabled() -- skipped until iOS has a debugger transport story.

    // Housekeeping wait loop, mirroring Android's RunEmulation shape (native.cpp): keeps this
    // thread parked (not busy-polling) for the lifetime of the emulation session so it can
    // observe HaltEmulation()'s m_cv.notify_one() and exit cleanly. Previously this function
    // returned immediately after Run(), so nothing on this thread ever waited for shutdown.
    //
    // TODO(ios): Android's version of this loop also polls for a pending disk-shader-cache
    // reload request (m_pending_shader_cache_title / RequestDiskShaderCacheReload) and services
    // it here. iOS has no such request queued anywhere yet (no member for it in native.h), so
    // this loop only handles the shutdown wait for now -- add the reload-request plumbing
    // alongside the shader cache preload TODO above if/when that's wired up.
    while (true) {
        std::unique_lock lock(m_mutex);
        if (m_cv.wait_for(lock, std::chrono::milliseconds(800),
                           [&]() { return !m_is_running.load(); })) {
            break;
        }
    }
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
