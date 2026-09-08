// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

#import "AetherBridge.h"

#include "ios/native.h"

#include <os/lock.h>

#import "ios/native_surface.h"

// native.h only forward-declares `struct AetherNativeSurface;` (deliberately opaque so
// that header has zero Objective-C dependency and stays includable from plain C++ TUs
// -- see its comment). The real definition lives in ios/native_surface.h so both this
// file and emu_window.mm (both .mm) can see it -- EmuWindow_iOS::OnSurfaceChanged now
// dereferences `->layer` to hand video_core the raw CAMetalLayer pointer.
//
// `layer` is a strong (ARC-retaining) reference, not __unsafe_unretained -- this struct
// lives inside AetherBridge, a process-lifetime singleton, so an unsafe_unretained field
// would outlive the CAMetalLayer it points to the moment the hosting view (MetalHostView,
// MetalView.swift) is torn down, since that view is the layer's only other owner.
// detachMetalLayer below clears it explicitly before that happens. Access is guarded by
// _surface.lock (defined on the struct itself, native_surface.h -- see its comment for
// why) since the emulation engine reads this from its own queue (EmuWindow_iOS::
// OnSurfaceChanged, both via SurfaceChanged() below and directly from EmuWindow_iOS's
// constructor on the emulation queue) while the main thread calls attachMetalLayer/
// detachMetalLayer during ordinary view lifecycle events.

@implementation AetherBridge {
    AetherNativeSurface _surface;
    dispatch_queue_t _emulationQueue;
    // Set by loadGameAtPath:completion: just before dispatching the load, cleared and
    // invoked (on the main queue) by the StateCallback registered below once the real
    // outcome is known. An adversarial review pass caught that this was assumed to be
    // "read/written only on _emulationQueue or synchronously before a dispatch_async onto
    // it" -- true for loadGameAtPath:'s own write and InitializeEmulation's own path, but
    // EmuWindow_iOS::OnFrameDisplayed (emu_window.mm) also calls into the StateCallback
    // via OnEmulationStarted from whatever thread the GPU/video thread runs on, which is
    // not necessarily _emulationQueue. Guarded by _pendingLoadCompletionLock instead.
    void (^_pendingLoadCompletion)(AetherLoadResult);
    os_unfair_lock _pendingLoadCompletionLock;
}

+ (instancetype)shared {
    static AetherBridge *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      instance = [AetherBridge new];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _emulationQueue = dispatch_queue_create("dev.aetheremu.emulation", DISPATCH_QUEUE_SERIAL);
        _surface.lock = OS_UNFAIR_LOCK_INIT;
        _pendingLoadCompletionLock = OS_UNFAIR_LOCK_INIT;

        // EmulationSession::OnEmulationStarted fires (synchronously, on _emulationQueue)
        // once InitializeEmulation actually succeeds -- this replaces the old
        // "loadGameAtPath: reports success optimistically" behavior with the real outcome.
        // OnEmulationStopped also routes here (e.g. a later HaltEmulation-driven teardown),
        // but by then _pendingLoadCompletion is already nil from the started callback, so
        // it's a harmless no-op in that case.
        __weak AetherBridge *weakSelf = self;
        EmulationSession::GetInstance().SetStateCallback(
            [weakSelf](bool /*success*/, Core::SystemResultStatus result) {
              AetherBridge *strongSelf = weakSelf;
              if (strongSelf == nil) {
                  return;
              }
              os_unfair_lock_lock(&strongSelf->_pendingLoadCompletionLock);
              void (^completion)(AetherLoadResult) = strongSelf->_pendingLoadCompletion;
              strongSelf->_pendingLoadCompletion = nil;
              os_unfair_lock_unlock(&strongSelf->_pendingLoadCompletionLock);
              if (completion == nil) {
                  return;
              }
              const AetherLoadResult load_result = result == Core::SystemResultStatus::Success
                                                       ? AetherLoadResultSuccess
                                                       : AetherLoadResultFailure;
              dispatch_async(dispatch_get_main_queue(), ^{
                completion(load_result);
              });
            });
    }
    return self;
}

- (void)initializeApplication:(NSString *)appSupportDirectory {
    EmulationSession::GetInstance().InitializeApplication(
        std::string([appSupportDirectory UTF8String]));
}

- (BOOL)installKeysAtPath:(NSString *)prodKeysPath {
    return EmulationSession::GetInstance().InstallKeys(std::string([prodKeysPath UTF8String]))
              ? YES
              : NO;
}

- (BOOL)installFirmwareAtPath:(NSString *)firmwareDirectory {
    return EmulationSession::GetInstance().InstallFirmware(
              std::string([firmwareDirectory UTF8String]))
              ? YES
              : NO;
}

- (BOOL)hasFirmwareInstalled {
    return EmulationSession::GetInstance().HasFirmwareInstalled() ? YES : NO;
}

- (NSString *)logDirectory {
    const std::string dir = EmulationSession::GetInstance().GetLogDirectory();
    return [NSString stringWithUTF8String:dir.c_str()];
}

- (void)attachMetalLayer:(CAMetalLayer *)layer {
    os_unfair_lock_lock(&_surface.lock);
    _surface.layer = layer;
    os_unfair_lock_unlock(&_surface.lock);
    EmulationSession::GetInstance().SetNativeSurface(&_surface);
    EmulationSession::GetInstance().SurfaceChanged();
}

- (void)detachMetalLayer {
    os_unfair_lock_lock(&_surface.lock);
    _surface.layer = nil;
    os_unfair_lock_unlock(&_surface.lock);

    // An adversarial review pass caught this being missing: clearing _surface.layer
    // above only fixes AetherBridge's own copy. EmuWindow_iOS::window_info.render_surface
    // (emu_window.mm's OnSurfaceChanged) still held a (__bridge void*) pointer to the
    // same CAMetalLayer -- once its sole strong (ARC) owner is gone, that's a dangling
    // pointer sitting in window_info until something overwrites it. SurfaceChanged()
    // re-reads m_native_surface (the same _surface struct, still a valid address --
    // only its .layer field changed to nil), and OnSurfaceChanged's existing
    // null-surface branch correctly resets render_surface to nullptr/type to Headless.
    EmulationSession::GetInstance().SurfaceChanged();
}

- (void)loadGameAtPath:(NSString *)path completion:(void (^)(AetherLoadResult result))completion {
    std::string cpath = std::string([path UTF8String]);
    os_unfair_lock_lock(&_pendingLoadCompletionLock);
    _pendingLoadCompletion = [completion copy];
    os_unfair_lock_unlock(&_pendingLoadCompletionLock);

    // TODO(ios): InitializeEmulation is currently a best-effort, untested implementation
    // (see native.mm) -- calling it on the emulation queue rather than the caller's
    // queue so this method itself stays non-blocking, but it doesn't validate real load
    // timing yet.
    //
    // NOTE(ios): ConfigureFilesystemProvider is intentionally NOT called here anymore --
    // InitializeEmulation now calls it internally (mirroring Android, whose JNI entry
    // point only calls InitializeEmulation and lets it call ConfigureFilesystemProvider
    // once system bring-up/InitializeSystem has run). Calling it from here first would
    // dereference m_manual_provider before InitializeEmulation's InitializeSystem() call
    // has constructed it.
    dispatch_async(_emulationQueue, ^{
      auto &session = EmulationSession::GetInstance();
      const auto result = session.InitializeEmulation(cpath);
      if (result == Core::SystemResultStatus::Success) {
          // Blocks this queue for the rest of the emulation session (see RunEmulation's
          // own comment) -- OnEmulationStarted has already fired (synchronously, inside
          // InitializeEmulation above) and resolved _pendingLoadCompletion by the time
          // control reaches here, so nothing below this line needs to touch it.
          session.RunEmulation();
      } else {
          NSLog(@"[AetherBridge] InitializeEmulation failed: %d", static_cast<int>(result));
          // InitializeEmulation returns early on failure without calling
          // OnEmulationStarted/OnEmulationStopped (see native.mm), so the state callback
          // never fires for this path -- resolve the completion directly instead.
          os_unfair_lock_lock(&self->_pendingLoadCompletionLock);
          void (^failureCompletion)(AetherLoadResult) = self->_pendingLoadCompletion;
          self->_pendingLoadCompletion = nil;
          os_unfair_lock_unlock(&self->_pendingLoadCompletionLock);
          if (failureCompletion != nil) {
              dispatch_async(dispatch_get_main_queue(), ^{
                failureCompletion(AetherLoadResultFailure);
              });
          }
      }
    });
}

// TODO(ios): untested, no CI oracle available -- mirrors Android's native_input.cpp
// IsRunning()-gated forwarding into EmuWindow_iOS::OnTouch*/*, but this is the first
// caller of those methods on iOS so the whole path is unverified end to end.
- (void)touchPressed:(NSInteger)touchId x:(float)x y:(float)y {
    if (!EmulationSession::GetInstance().IsRunning()) {
        return;
    }
    EmulationSession::GetInstance().Window().OnTouchPressed(static_cast<int>(touchId), x, y);
}

- (void)touchMoved:(NSInteger)touchId x:(float)x y:(float)y {
    if (!EmulationSession::GetInstance().IsRunning()) {
        return;
    }
    EmulationSession::GetInstance().Window().OnTouchMoved(static_cast<int>(touchId), x, y);
}

- (void)touchReleased:(NSInteger)touchId {
    if (!EmulationSession::GetInstance().IsRunning()) {
        return;
    }
    EmulationSession::GetInstance().Window().OnTouchReleased(static_cast<int>(touchId));
}

- (void)pause {
    EmulationSession::GetInstance().PauseEmulation();
}

- (void)resume {
    EmulationSession::GetInstance().UnPauseEmulation();
}

- (void)shutdown {
    EmulationSession::GetInstance().HaltEmulation();
}

- (BOOL)isRunning {
    return EmulationSession::GetInstance().IsRunning();
}

- (BOOL)isPaused {
    return EmulationSession::GetInstance().IsPaused();
}

@end
