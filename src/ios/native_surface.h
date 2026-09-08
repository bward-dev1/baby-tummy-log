// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#import <QuartzCore/QuartzCore.h>

// Real definition of the surface handed from Swift down into the emulation core.
// `layer` is a strong (ARC) ref -- see AetherBridge.mm/emu_window.mm for lifecycle notes.
//
// This header is Objective-C++ only (imports QuartzCore) and must only be included from
// .mm translation units. core/frontend-facing headers (e.g. ios/emu_window/emu_window.h,
// ios/native.h) stay ObjC-free and only forward-declare `struct AetherNativeSurface;`.
struct AetherNativeSurface {
    CAMetalLayer *layer;
};
