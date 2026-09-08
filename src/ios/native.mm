// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

// Every other platform's entry point defines VMA_IMPLEMENTATION exactly once to
// actually compile Vulkan Memory Allocator's function bodies (it's a single-header
// library, header-only until something does this) -- yuzu/main_window.cpp (Qt),
// yuzu_cmd/yuzu.cpp (CLI), android/app/src/main/jni/native.cpp (Android). iOS had none,
// which a real CI link failure caught: "_vmaInvalidateAllocation"/"_vmaUnmapMemory"
// undefined, referenced from video_core's own vulkan_wrapper.o/vulkan_memory_allocator.o
// -- not a missing-library linker-flags problem (those .o files DO get compiled and
// archived into libvideo_core.a; the vma* symbols they call just never existed
// anywhere in the whole link, since nothing on this platform ever defined
// VMA_IMPLEMENTATION). native.mm is EmulationSession's own translation unit and the
// sole iOS entry point, so this is the correct (and only) place for it on this
// platform, mirroring the other platforms' pattern exactly.
//
// The pragma push/pop around this is load-bearing, not decorative: src/CMakeLists.txt's
// ENABLE_WERROR block turns -Wunused (among others) into a hard error project-wide, and
// vk_mem_alloc.h's own implementation section has a handful of genuinely unused
// variables in its third-party source -- a real CI failure caught this too, once the
// missing-VMA_IMPLEMENTATION fix above got far enough to actually compile this header.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"
#define VMA_IMPLEMENTATION
#include "video_core/vulkan_common/vma.h"
#pragma clang diagnostic pop

#include "ios/native.h"

#include <chrono>
#include <utility>

#include "common/fs/fs.h"
#include "common/fs/path_util.h"
#include "common/logging.h"
#include "common/settings.h"
#include "core/cpu_manager.h"
#include "core/file_sys/content_archive.h"
#include "core/file_sys/vfs/vfs.h"
#include "core/file_sys/vfs/vfs_real.h"
#include "core/hle/service/am/applet_manager.h"
#include "core/hle/service/filesystem/filesystem.h"
#include "core/loader/loader.h"
#include "frontend_common/firmware_manager.h"
#include "hid_core/hid_core.h"
#include "video_core/gpu.h"
#include "video_core/renderer_base.h"

namespace {
EmulationSession s_instance;
}

EmulationSession::EmulationSession() {
    m_vfs = std::make_shared<FileSys::RealVfsFilesystem>();
}

EmulationSession& EmulationSession::GetInstance() {
    return s_instance;
}

void EmulationSession::InitializeApplication(const std::string& app_support_dir) {
    if (m_app_initialized) {
        return;
    }
    m_app_initialized = true;

    // Points every Common::FS::EdenPath (keys, NAND, saves, logs, ...) at the real
    // sandboxed directory the caller chose (see path_util.cpp's TARGET_OS_IOS branch --
    // without this, iOS's Reinitialize() ASSERTs on an empty path, exactly like Android's
    // equivalent branch does when SetAppDirectory is never called).
    Common::FS::SetAppDirectory(app_support_dir);
    Common::FS::CreateEdenPaths();

    // Was never called anywhere on iOS before this -- every LOG_INFO/LOG_ERROR call in
    // this whole port was silently going nowhere. Mirrors Android's InitializeSystem
    // (native.cpp): Initialize() creates the file backend (EdenPath::LogDir/eden_log.txt,
    // see logging.cpp), the color console backend is genuinely useful when run/debugged
    // from Xcode's console, and Start() begins the logger thread.
    Common::Log::Initialize();
    Common::Log::SetColorConsoleBackendEnabled(true);
    Common::Log::Start();

    LOG_INFO(Frontend, "EmulationSession::InitializeApplication: app_support_dir={}",
              app_support_dir);
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
    // An adversarial review pass caught this missing: InitializeEmulation and
    // SurfaceChanged both read m_native_surface under m_mutex, but this write wasn't
    // locked at all -- a genuine data race if attachMetalLayer's first call (main thread)
    // ever coincides with InitializeEmulation constructing EmuWindow_iOS (emulation queue).
    std::scoped_lock lock(m_mutex);
    m_native_surface = native_surface;
}

void EmulationSession::SurfaceChanged() {
    // Locking m_mutex here (an adversarial review pass caught this missing) matters for
    // two things at once: it serializes against InitializeEmulation, which constructs
    // m_window and later calls GPU().Start() (reading window_info) while holding this
    // same mutex -- without the lock, a resize/rotation landing on the main thread
    // during startup could write window_info concurrently with that read. It also
    // avoids racing ShutdownEmulation's m_window.reset() (also under m_mutex) --
    // currently unreachable since nothing calls ShutdownEmulation yet, but this closes
    // that race preemptively rather than leaving it for whoever wires up teardown.
    std::scoped_lock lock(m_mutex);
    if (!m_is_running || !m_window) {
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
    // filesystem/content-provider bring-up. Skips Android's `!reload` branch inside that
    // function (log-system Common::Log::Initialize/Start + m_input_subsystem.Initialize()):
    // those are one-time process bring-up steps that belong in whatever iOS app-launch
    // path constructs this singleton, not here, and there is no `reload` concept on iOS
    // yet (no re-launch/program-select flow exists). Revisit if iOS grows a reload path
    // that needs to skip re-registering the content provider.
    //
    // An adversarial review pass caught a separate, real gap here: Android's JNI
    // initializeSystem wrapper ALSO calls `System().Initialize()` directly (outside
    // EmulationSession::InitializeSystem entirely) on first launch -- that call was never
    // ported to iOS at all. It wasn't crashing only because Core::System::Impl::Load()
    // lazily calls Initialize() itself the first time (ReinitializeIfNecessary() checks an
    // unpopulated device_memory optional) -- an internal fallback for a changed
    // multicore/memory-layout setting mid-session, not a substitute for this one-time
    // bring-up call. Calling it explicitly here, once, matches Android's intent.
    if (!m_system_initialized) {
        m_system.Initialize();
        m_system_initialized = true;
    }

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

bool EmulationSession::InstallKeys(const std::string& prod_keys_path) {
    // FirmwareManager::InstallKeys's non-Android branch is already platform-agnostic
    // std::filesystem code (checks the filename ends with "prod.keys", looks alongside it
    // for title.keys/key_retail.bin, copies whichever exist into EdenPath::KeysDir, then
    // reloads Core::Crypto::KeyManager) -- no Qt/JNI involved, safe to call directly.
    const auto result = FirmwareManager::InstallKeys(prod_keys_path, "prod.keys");
    if (result != FirmwareManager::Success) {
        LOG_ERROR(Frontend, "InstallKeys failed: {}", static_cast<int>(result));
        return false;
    }
    LOG_INFO(Frontend, "InstallKeys succeeded from {}", prod_keys_path);
    return true;
}

bool EmulationSession::InstallFirmware(const std::string& firmware_dir_path) {
    // Reimplements QtCommon::Content::InstallFirmware's core logic (content.cpp) against
    // this session's own m_system/m_vfs instead of Qt's global system/vfs pointers --
    // that version also drives a Qt progress dialog and QFuture concurrency this doesn't
    // need. Non-recursive by design: the common case (and the only one the Settings UI
    // offers) is importing a flat folder of firmware NCAs, e.g. after the user extracts
    // Nintendo's own firmware archive themselves -- recursive/zip-archive import is a
    // real, documented gap (see SettingsView.swift), not something guessed at here.
    {
        // A user installing firmware as their very first action (before ever loading a
        // game) would otherwise hit GetFileSystemController() with no factories created
        // yet -- InitializeSystem() is idempotent (m_system_initialized), so this is safe
        // to call unconditionally rather than assuming InitializeEmulation ran first.
        std::scoped_lock lock(m_mutex);
        InitializeSystem();
    }

    const std::filesystem::path firmware_source_path = firmware_dir_path;
    if (!Common::FS::IsDir(firmware_source_path)) {
        LOG_ERROR(Frontend, "InstallFirmware: {} is not a directory", firmware_dir_path);
        return false;
    }

    std::vector<std::filesystem::path> nca_files;
    const Common::FS::DirEntryCallable collect_ncas =
        [&nca_files](const std::filesystem::directory_entry& entry) {
            if (entry.path().has_extension() && entry.path().extension() == ".nca") {
                nca_files.emplace_back(entry.path());
            }
            return true;
        };
    Common::FS::IterateDirEntries(firmware_source_path, collect_ncas,
                                  Common::FS::DirEntryFilter::File);

    if (nca_files.empty()) {
        LOG_ERROR(Frontend, "InstallFirmware: no .nca files found in {}", firmware_dir_path);
        return false;
    }

    auto sysnand_content_vdir = m_system.GetFileSystemController().GetSystemNANDContentDirectory();
    if (!sysnand_content_vdir) {
        LOG_ERROR(Frontend, "InstallFirmware: no system NAND content directory");
        return false;
    }
    if (sysnand_content_vdir->IsWritable() &&
        !sysnand_content_vdir->CleanSubdirectoryRecursive("registered")) {
        LOG_ERROR(Frontend, "InstallFirmware: failed to clean the registered/ directory");
        return false;
    }

    auto firmware_vdir = sysnand_content_vdir->GetDirectoryRelative("registered");
    bool success = true;
    for (const auto& nca_path : nca_files) {
        auto src = m_vfs->OpenFile(nca_path.generic_string(), FileSys::OpenMode::Read);
        auto dst = firmware_vdir->CreateFileRelative(nca_path.filename().string());
        if (!src || !dst || !FileSys::VfsRawCopy(src, dst)) {
            LOG_ERROR(Frontend, "InstallFirmware: failed to copy {}", nca_path.string());
            success = false;
        }
    }

    if (!success) {
        return false;
    }

    // Re-scan the VFS for the newly placed firmware files, mirroring content.cpp.
    m_system.GetFileSystemController().CreateFactories(*m_vfs);
    LOG_INFO(Frontend, "InstallFirmware installed {} NCA file(s) from {}", nca_files.size(),
              firmware_dir_path);
    return true;
}

bool EmulationSession::HasFirmwareInstalled() {
    return FirmwareManager::CheckFirmwarePresence(m_system);
}

std::string EmulationSession::GetLogDirectory() const {
    return Common::FS::GetEdenPathString(Common::FS::EdenPath::LogDir);
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
    // AndroidWebBrowser, JNI-backed implementations with no iOS equivalent yet. This is
    // safe to leave unset, not just "the honest interim state": Core::System::Impl::
    // Initialize() (core/core.cpp) already calls FrontendAppletHolder::
    // SetDefaultAppletsIfMissing() for every slot the frontend never filled in, and
    // DefaultSoftwareKeyboardApplet (core/frontend/applets/software_keyboard.cpp) never
    // crashes -- ShowNormalKeyboard just auto-submits a fixed string via the normal
    // callback, everything else is a LOG_WARNING stub. A title that invokes the software
    // keyboard applet will get that default behavior rather than a real on-screen
    // keyboard, which is a real UX gap once there's a UI to wire an iOS one into, but not
    // a crash risk.

    ConfigureFilesystemProvider(filepath);

    // A default-constructed FrontendAppletParameters was a real, confirmed boot-blocking
    // bug, not just an honest stub: applet_id{} value-initializes to AppletId::None (0x00),
    // and applet_manager.cpp's CreateApplet reads `params.applet_id == AppletId::Application`
    // directly as the "is this actually the game, not some other applet" flag passed to the
    // new Applet's constructor -- with None, the freshly-loaded game process would never be
    // treated as the application at all, regardless of whether the load/JIT/rendering below
    // succeeds. program_id/program_index/previous_program_index (sub-program relaunch state)
    // remain a real TODO -- there's no frontend UI driving those yet -- but applet_id/
    // applet_type/launch_type need to be correct for ANY title to boot as a game, not just
    // for the sub-program-relaunch case, so they're set explicitly here rather than left
    // default-constructed. Mirrors Android's own default (m_applet_id{1} == Application).
    Service::AM::FrontendAppletParameters params{
        .applet_id = Service::AM::AppletId::Application,
        .applet_type = Service::AM::AppletType::Application,
        .launch_type = Service::AM::LaunchType::FrontendInitiated,
    };
    m_load_result = m_system.Load(*m_window, filepath, params);
    if (m_load_result != Core::SystemResultStatus::Success) {
        return m_load_result;
    }

    m_system.GPU().Start();
    m_system.GetCpuManager().OnGpuReady();
    m_system.RegisterExitCallback([&] { HaltEmulation(); });

    // Mirrors Android's equivalent registration -- without this, RequestDiskShaderCacheReload
    // (native.h) had no caller anywhere in this codebase, so a title changing its running
    // program (DLC, some multi-program titles) would never actually trigger the reload path
    // RunEmulation's wait loop already implements.
    m_system.RegisterApplicationChangedCallback(
        [this](u64 changed_program_id) { RequestDiskShaderCacheReload(changed_program_id); });

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
    // Preload the disk shader cache for the title that was just loaded, mirroring
    // Android's RunEmulation -- LoadDiskCacheProgress below is a real, logging-based
    // progress report rather than a fabricated UI callback (iOS has no progress dialog
    // to report to yet).
    if (Settings::values.use_disk_shader_cache.GetValue()) {
        LoadDiskCacheProgress(VideoCore::LoadCallbackStage::Prepare, 0, 0);
        m_system.Renderer().ReadRasterizer()->LoadDiskResources(
            m_system.GetApplicationProcessProgramID(), std::stop_token{}, LoadDiskCacheProgress);
        LoadDiskCacheProgress(VideoCore::LoadCallbackStage::Complete, 0, 0);
    }

    void(m_system.Run());

    // TODO(ios): Android also calls m_system.InitializeDebugger() here when
    // m_system.DebuggerEnabled() -- skipped until iOS has a debugger transport story.

    // Housekeeping wait loop, mirroring Android's RunEmulation shape (native.cpp): keeps this
    // thread parked (not busy-polling) for the lifetime of the emulation session so it can
    // observe HaltEmulation()'s m_cv.notify_one() and exit cleanly, and services any pending
    // disk-shader-cache reload request queued by RequestDiskShaderCacheReload.
    while (true) {
        std::optional<u64> reload_title;
        {
            std::unique_lock lock(m_mutex);
            if (m_cv.wait_for(lock, std::chrono::milliseconds(800), [&]() {
                    return !m_is_running.load() || m_pending_shader_cache_title.has_value();
                })) {
                if (!m_is_running) {
                    break;
                }
                reload_title = std::exchange(m_pending_shader_cache_title, std::nullopt);
            }
        }

        if (reload_title.has_value()) {
            ReloadDiskShaderCache(*reload_title);
        }
    }
}

void EmulationSession::RequestDiskShaderCacheReload(u64 program_id) {
    {
        std::scoped_lock lock(m_mutex);
        m_pending_shader_cache_title = program_id;
    }
    m_cv.notify_one();
}

void EmulationSession::ReloadDiskShaderCache(u64 program_id) {
    if (!Settings::values.use_disk_shader_cache.GetValue()) {
        return;
    }

    // An adversarial review pass caught this missing: PauseEmulation/UnPauseEmulation
    // hold m_mutex around the equivalent m_system.Pause()/Run() calls, but this function
    // -- called from RunEmulation's wait loop after it releases its own lock -- didn't,
    // letting a shader-cache reload race a user-initiated pause/resume (AetherBridge's
    // -pause/-resume) touching the same Core::System pause/run state and GPU context
    // concurrently with no mutual exclusion.
    std::scoped_lock lock(m_mutex);

    LOG_INFO(Frontend, "Reloading disk shader cache for {:016X}", program_id);

    const bool was_paused = m_is_paused;

    m_system.Pause();
    m_system.GPU().WaitForIdle();
    m_system.GPU().ObtainContext();

    LoadDiskCacheProgress(VideoCore::LoadCallbackStage::Prepare, 0, 0);
    m_system.Renderer().ReadRasterizer()->LoadDiskResources(program_id, std::stop_token{},
                                                           LoadDiskCacheProgress);
    LoadDiskCacheProgress(VideoCore::LoadCallbackStage::Complete, 0, 0);

    m_system.GPU().ReleaseContext();

    if (!was_paused) {
        m_system.Run();
    }
}

void EmulationSession::LoadDiskCacheProgress(VideoCore::LoadCallbackStage stage,
                                             std::size_t progress, std::size_t max) {
    LOG_INFO(Frontend, "Disk shader cache load progress: stage={} progress={}/{}",
              static_cast<int>(stage), progress, max);
}

void EmulationSession::SetStateCallback(StateCallback callback) {
    std::scoped_lock lock(m_mutex);
    m_state_callback = std::move(callback);
}

// Android notifies the Kotlin frontend via a JNI static-method callback here. There's no
// JNI on this platform -- AetherBridge registers a StateCallback (see native.h) that wraps
// this back into a completion block for loadGameAtPath:completion:.
//
// NOTE(ios): m_state_callback is read here without m_mutex, unlike SetStateCallback's
// locked write -- both InitializeEmulation and ShutdownEmulation already hold m_mutex when
// they call this, so taking it again here would deadlock. In practice SetStateCallback is
// only ever called once, from AetherBridge's -init, before any load can happen, so this is
// a narrow/theoretical race rather than a live one; revisit if a callback re-registration
// path is ever added.
void EmulationSession::OnEmulationStarted() {
    LOG_INFO(Frontend, "EmulationSession::OnEmulationStarted");
    if (m_state_callback) {
        m_state_callback(true, Core::SystemResultStatus::Success);
    }
}

void EmulationSession::OnEmulationStopped(Core::SystemResultStatus result) {
    LOG_INFO(Frontend, "EmulationSession::OnEmulationStopped: {}", static_cast<int>(result));
    if (m_state_callback) {
        m_state_callback(false, result);
    }
}
