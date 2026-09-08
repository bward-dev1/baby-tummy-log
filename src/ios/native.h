// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <atomic>
#include <condition_variable>
#include <functional>
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

    // One-time process bring-up: points Common::FS's EdenPath machinery at a real
    // writable sandbox directory (Application Support, chosen by the caller) and starts
    // the logging system. Must run before InitializeSystem/InitializeEmulation and before
    // any InstallKeys/InstallFirmware call. Idempotent -- a second call is a harmless
    // no-op, matching InitializeSystem's own m_system_initialized guard below.
    //
    // Previously never called on iOS at all (native.h's own InitializeSystem comment used
    // to say logging bring-up "belongs in whatever iOS app-launch path constructs this
    // singleton, not here" -- but nothing ever called it there either, so every LOG_INFO/
    // LOG_ERROR call in this whole iOS port was silently going nowhere). AetherEMUApp.swift
    // now calls this at app launch via AetherBridge.
    void InitializeApplication(const std::string& app_support_dir);

    // Copies prod.keys from `prod_keys_path` into EdenPath::KeysDir and reloads
    // Core::Crypto::KeyManager. Deliberately does NOT scan for sibling title.keys/
    // key_retail.bin the way FirmwareManager::InstallKeys's desktop/Android path does --
    // iOS's single-file document-picker grant only covers the picked file itself, not its
    // parent directory, so that scan always failed with InvalidDir on a real device. See
    // native.mm's InstallKeys for the full explanation.
    bool InstallKeys(const std::string& prod_keys_path);

    // Copies every .nca file directly inside `firmware_dir_path` (non-recursive -- the
    // common case is a flat folder of firmware NCAs, e.g. after extracting Nintendo's own
    // firmware archive) into the emulated system NAND's registered-content directory,
    // replacing whatever was there, then re-scans the VFS. Reimplements
    // QtCommon::Content::InstallFirmware's core logic against this session's own
    // m_system/m_vfs instead of Qt's global system/vfs pointers (that file also drives a
    // Qt progress dialog and QFuture concurrency this doesn't need -- call from a
    // background queue on the Swift side instead, same as loadGameAtPath:completion:).
    bool InstallFirmware(const std::string& firmware_dir_path);

    // Wraps FirmwareManager::CheckFirmwarePresence -- true once InstallFirmware has
    // actually placed a Mii Edit applet NCA (or equivalent) in the system NAND.
    bool HasFirmwareInstalled();

    // The directory logs are written to (EdenPath::LogDir) -- AetherBridge exposes this
    // so Swift can list/share the log files a user might attach to a bug report.
    std::string GetLogDirectory() const;

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

    // Fired from OnEmulationStarted/OnEmulationStopped below -- the frontend (AetherBridge)
    // registers one of these to learn the real outcome of a load, replacing the old
    // "report success optimistically before the async load even runs" behavior. Runs
    // synchronously on whatever thread InitializeEmulation/ShutdownEmulation is running on
    // (the bridge's serial emulation queue) -- callers that touch UI must hop to the main
    // queue themselves rather than assume this fires there.
    using StateCallback = std::function<void(bool success, Core::SystemResultStatus result)>;
    void SetStateCallback(StateCallback callback);

    void OnEmulationStarted();

    // Requests a disk shader cache reload for the given title, mirroring Android's
    // JNI-callable entry point of the same name (native.cpp). Thread-safe: queues the
    // request and wakes RunEmulation's wait loop, which services it via
    // ReloadDiskShaderCache below rather than reloading inline on the caller's thread.
    void RequestDiskShaderCacheReload(u64 program_id);

private:
    void OnEmulationStopped(Core::SystemResultStatus result);

    // Pauses the GPU, reloads the disk shader cache for `program_id`, then resumes --
    // mirrors Android's ReloadDiskShaderCache. Only ever called from RunEmulation's wait
    // loop (see native.mm), never directly from RequestDiskShaderCacheReload's caller
    // thread, so it doesn't need its own locking beyond what m_system already provides.
    void ReloadDiskShaderCache(u64 program_id);

    // Logs shader-cache load progress. iOS has no progress-bar UI to report to yet
    // (unlike Android's JNI callback into a Kotlin progress dialog), so this is a real,
    // functioning stand-in rather than a fabricated frontend hook -- matches this file's
    // existing pattern of logging honestly instead of guessing at UI that doesn't exist.
    static void LoadDiskCacheProgress(VideoCore::LoadCallbackStage stage, std::size_t progress,
                                      std::size_t max);

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
    // Guards InitializeApplication above, the same way m_system_initialized guards
    // InitializeSystem -- both are "has this process-wide singleton done its one-time
    // bring-up" flags, not a reload/relaunch distinction.
    bool m_app_initialized{false};
    std::atomic<bool> m_is_running = false;
    std::atomic<bool> m_is_paused = false;
    std::unique_ptr<FileSys::ManualContentProvider> m_manual_provider;
    StateCallback m_state_callback;
    // Set by RequestDiskShaderCacheReload, consumed by RunEmulation's wait loop -- mirrors
    // Android's m_pending_shader_cache_title.
    std::optional<u64> m_pending_shader_cache_title;

    // GPU driver parameters
    std::shared_ptr<Common::DynamicLibrary> m_vulkan_library;

    // Synchronization
    std::condition_variable_any m_cv;
    mutable std::mutex m_mutex;
};
