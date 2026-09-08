// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// Objective-C-facing surface of EmulationSession (src/ios/native.h). Swift can't call
// C++ directly, so this is the thin translation layer: a plain NSObject subclass with
// primitive/Foundation types in its interface, backed by an .mm implementation that's
// free to touch the real C++ engine. Kept intentionally small -- mirror Android's JNI
// entry points (src/android/app/src/main/jni/native.cpp) one at a time as the Swift UI
// grows, rather than exposing the whole EmulationSession surface up front.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AetherLoadResult) {
    AetherLoadResultSuccess = 0,
    AetherLoadResultFailure = 1,
};

@interface AetherBridge : NSObject

+ (instancetype)shared;

/// Hands the engine a CAMetalLayer to render into. Call again after a layer resize or
/// after the app returns from background (the layer's drawable size may have changed).
- (void)attachMetalLayer:(CAMetalLayer *)layer;

/// Loads a game image (NSP/XCI/NCA) from an already security-scoped-accessible path
/// and starts emulation on a background thread. Returns immediately.
- (AetherLoadResult)loadGameAtPath:(NSString *)path;

- (void)pause;
- (void)resume;
- (void)shutdown;

@property(nonatomic, readonly) BOOL isRunning;
@property(nonatomic, readonly) BOOL isPaused;

@end

NS_ASSUME_NONNULL_END
