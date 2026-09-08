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

/// Must be called once, as early as possible (AetherEMUApp.swift's init), before any
/// other method on this class. Points the engine's EdenPath machinery at a real writable
/// sandbox directory and starts the logging system -- previously nothing on iOS ever
/// called the C++-side equivalent at all, so every log line in this whole port went
/// nowhere. `appSupportDirectory` should be a path under
/// FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask) that
/// the caller has already created. Safe to call more than once (a no-op after the first).
- (void)initializeApplication:(NSString *)appSupportDirectory;

/// Copies prod.keys (and title.keys/key_retail.bin alongside it, if present) into the
/// engine's keys directory and reloads the key manager. `prodKeysPath` must point
/// directly at a file named prod.keys -- title.keys/key_retail.bin are discovered
/// automatically from the same parent directory. Returns NO if prod.keys wasn't found
/// or the copy failed; check the log (see logDirectory below) for the specific reason.
- (BOOL)installKeysAtPath:(NSString *)prodKeysPath;

/// Copies every .nca file found directly inside `firmwareDirectory` (not recursive) into
/// the emulated system NAND, replacing any firmware installed previously. Point this at
/// a folder of firmware NCAs (e.g. after extracting Nintendo's own firmware archive) --
/// picking a .zip directly is not supported yet. Synchronous and can take a few seconds
/// for a full firmware set; call from a background queue, not the main thread.
- (BOOL)installFirmwareAtPath:(NSString *)firmwareDirectory;

/// Whether InstallFirmware has placed usable firmware in the emulated system NAND.
@property(nonatomic, readonly) BOOL hasFirmwareInstalled;

/// Directory the engine writes its log files to (see LOG_FILE, currently
/// "eden_log.txt") -- for a Settings-screen log viewer/share sheet.
@property(nonatomic, readonly) NSString *logDirectory;

/// Hands the engine a CAMetalLayer to render into. Call again after a layer resize or
/// after the app returns from background (the layer's drawable size may have changed).
/// NS_SWIFT_NAME pins the Swift-visible name -- Swift's importer otherwise auto-strips
/// "MetalLayer" from the selector since it matches the parameter's type name, silently
/// renaming this to attach(_:) and breaking every existing MetalView.swift call site
/// (a real CI failure this caught: "'attachMetalLayer' has been renamed to 'attach(_:)'").
- (void)attachMetalLayer:(CAMetalLayer *)layer NS_SWIFT_NAME(attachMetalLayer(_:));

/// Call from the hosting view's teardown (e.g. willMove(toWindow: nil)) before its
/// CAMetalLayer deallocates. Without this, the engine's stored surface pointer would
/// outlive the layer it points to -- see AetherBridge.mm's AetherNativeSurface comment.
- (void)detachMetalLayer;

/// Loads a game image (NSP/XCI/NCA) from an already security-scoped-accessible path and
/// starts emulation on a background thread. `completion` is called on the main queue once
/// the real outcome is known (EmulationSession::OnEmulationStarted, or immediately if
/// InitializeEmulation itself fails) -- callers that hold a security-scoped resource open
/// for `path` must keep it open until `completion` runs, not just until this method returns.
- (void)loadGameAtPath:(NSString *)path completion:(void (^)(AetherLoadResult result))completion;

/// Forwards a touch-down event. `x`/`y` must be in the CAMetalLayer's pixel space
/// (i.e. view-point coords already multiplied by contentScaleFactor), matching the
/// drawableSize set in MetalHostView.layoutSubviews. `touchId` should be a stable
/// per-finger identifier (UITouch's hash or an assigned index) fitting in `int`.
- (void)touchPressed:(NSInteger)touchId x:(float)x y:(float)y;
- (void)touchMoved:(NSInteger)touchId x:(float)x y:(float)y;
- (void)touchReleased:(NSInteger)touchId;

- (void)pause;
- (void)resume;
- (void)shutdown;

@property(nonatomic, readonly) BOOL isRunning;
@property(nonatomic, readonly) BOOL isPaused;

@end

NS_ASSUME_NONNULL_END
