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
// _surfaceLock since the emulation engine may eventually read this from its own queue
// (see EmuWindow_iOS's TODOs) while the main thread calls attachMetalLayer/
// detachMetalLayer during ordinary view lifecycle events.

@implementation AetherBridge {
    AetherNativeSurface _surface;
    os_unfair_lock _surfaceLock;
    dispatch_queue_t _emulationQueue;
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
        _surfaceLock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (void)attachMetalLayer:(CAMetalLayer *)layer {
    os_unfair_lock_lock(&_surfaceLock);
    _surface.layer = layer;
    os_unfair_lock_unlock(&_surfaceLock);
    EmulationSession::GetInstance().SetNativeSurface(&_surface);
    EmulationSession::GetInstance().SurfaceChanged();
}

- (void)detachMetalLayer {
    os_unfair_lock_lock(&_surfaceLock);
    _surface.layer = nil;
    os_unfair_lock_unlock(&_surfaceLock);

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

- (AetherLoadResult)loadGameAtPath:(NSString *)path {
    std::string cpath = std::string([path UTF8String]);

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
          session.RunEmulation();
      } else {
          NSLog(@"[AetherBridge] InitializeEmulation failed: %d", static_cast<int>(result));
      }
    });

    // Real success/failure is only known after the async load above completes --
    // there's no callback wired yet (EmulationSession::OnEmulationStarted/Stopped are
    // still stub logging, see native.mm). Report optimistically for now; a future pass
    // should thread a completion block through instead of returning eagerly.
    return AetherLoadResultSuccess;
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
