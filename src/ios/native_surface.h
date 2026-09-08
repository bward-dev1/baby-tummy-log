// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#import <QuartzCore/QuartzCore.h>
#include <os/lock.h>

// Real definition of the surface handed from Swift down into the emulation core.
// `layer` is a strong (ARC) ref -- see AetherBridge.mm/emu_window.mm for lifecycle notes.
//
// This header is Objective-C++ only (imports QuartzCore) and must only be included from
// .mm translation units. core/frontend-facing headers (e.g. ios/emu_window/emu_window.h,
// ios/native.h) stay ObjC-free and only forward-declare `struct AetherNativeSurface;`.
//
// `lock` guards `layer` and lives HERE (on the shared struct) rather than as a separate
// ivar on AetherBridge, specifically so that every reader/writer of `layer` -- regardless
// of which file or thread it runs on -- synchronizes against the exact same lock. An
// adversarial review pass caught this being missing: AetherBridge.mm's attachMetalLayer/
// detachMetalLayer used to guard their own write with a private os_unfair_lock ivar, but
// EmuWindow_iOS::OnSurfaceChanged (emu_window.mm) -- which can run on the emulation queue,
// not just synchronously from AetherBridge -- read `surface->layer` with no lock at all,
// racing detachMetalLayer's concurrent write/release. Not reentrant: never call a function
// that re-locks this from inside a locked section.
struct AetherNativeSurface {
    CAMetalLayer *layer;
    os_unfair_lock lock;
};
