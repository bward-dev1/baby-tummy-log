// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

#import "AetherBridge.h"

#include "ios/native.h"

// native.h only forward-declares `struct AetherNativeSurface;` (deliberately opaque so
// that header has zero Objective-C dependency and stays includable from plain C++ TUs
// -- see its comment). This is the one place it's actually defined, wrapping the
// CAMetalLayer Swift hands us. EmuWindow_iOS/GraphicsContext_iOS never dereference it
// today (see emu_window.h's TODOs), so no other translation unit needs this definition
// yet -- when Metal rendering is wired up, whatever reads the layer to build a
// CAMetalDrawable will need to move into an .mm file that includes this header too.
struct AetherNativeSurface {
    CAMetalLayer *__unsafe_unretained layer;
};

@implementation AetherBridge {
    AetherNativeSurface _surface;
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
    }
    return self;
}

- (void)attachMetalLayer:(CAMetalLayer *)layer {
    _surface.layer = layer;
    EmulationSession::GetInstance().SetNativeSurface(&_surface);
    EmulationSession::GetInstance().SurfaceChanged();
}

- (AetherLoadResult)loadGameAtPath:(NSString *)path {
    std::string cpath = std::string([path UTF8String]);

    // TODO(ios): ConfigureFilesystemProvider/InitializeEmulation are currently
    // synchronous stubs (see native.mm) -- calling them on the emulation queue rather
    // than the caller's queue so this method itself stays non-blocking, but neither
    // does real I/O yet, so this doesn't validate real load timing.
    dispatch_async(_emulationQueue, ^{
      auto &session = EmulationSession::GetInstance();
      session.ConfigureFilesystemProvider(cpath);
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
