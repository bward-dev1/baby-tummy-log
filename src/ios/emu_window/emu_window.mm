// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#include "ios/emu_window/emu_window.h"

#include "common/logging.h"
#include "input_common/drivers/touch_screen.h"
#include "input_common/main.h"
#include "ios/native.h"

// TODO(ios): Real implementation needs to pull the CAMetalLayer's drawableSize out of
// `surface` here (this .mm file can freely mix Objective-C++ since it's not included
// from plain-C++ TUs -- only emu_window.h needs to stay ObjC-free). For now this is a
// stub that satisfies the linker and lets the CI CMake configure/generate step succeed;
// it does not touch a real surface at all.
void EmuWindow_iOS::OnSurfaceChanged(AetherNativeSurface* surface) {
    if (!surface) {
        LOG_INFO(Frontend, "EmuWindow_iOS::OnSurfaceChanged received null surface");
        m_window_width = 0;
        m_window_height = 0;
        window_info.render_surface = nullptr;
        return;
    }

    // TODO(ios): Replace with the real CAMetalLayer drawableSize once there's a device
    // to test against.
    window_info.render_surface = reinterpret_cast<void*>(surface);
    UpdateCurrentFramebufferLayout(m_window_width, m_window_height);
}

// TODO(ios): Route these from UIKit UITouch/UIGestureRecognizer callbacks once there's
// an app target and view hierarchy to receive them from.
void EmuWindow_iOS::OnTouchPressed(int id, float x, float y) {
    const auto [touch_x, touch_y] = MapToTouchScreen(x, y);
    EmulationSession::GetInstance().GetInputSubsystem().GetTouchScreen()->TouchPressed(touch_x,
                                                                                        touch_y, id);
}

void EmuWindow_iOS::OnTouchMoved(int id, float x, float y) {
    const auto [touch_x, touch_y] = MapToTouchScreen(x, y);
    EmulationSession::GetInstance().GetInputSubsystem().GetTouchScreen()->TouchMoved(touch_x,
                                                                                      touch_y, id);
}

void EmuWindow_iOS::OnTouchReleased(int id) {
    EmulationSession::GetInstance().GetInputSubsystem().GetTouchScreen()->TouchReleased(id);
}

// TODO(ios): Once a real Metal-backed view exists, this should signal `OnEmulationStarted()`
// on first frame the way EmuWindow_Android does via a JNI fiber hop; there's no JNI here,
// so that plumbing needs an iOS-appropriate replacement (e.g. dispatch to main queue).
void EmuWindow_iOS::OnFrameDisplayed() {
    if (!m_first_frame) {
        EmulationSession::GetInstance().OnEmulationStarted();
        m_first_frame = true;
    }
}

EmuWindow_iOS::EmuWindow_iOS(AetherNativeSurface* surface,
                             std::shared_ptr<Common::DynamicLibrary> driver_library)
    : m_driver_library{driver_library} {
    LOG_INFO(Frontend, "initializing");

    if (!surface) {
        LOG_CRITICAL(Frontend, "surface is nullptr");
        return;
    }

    OnSurfaceChanged(surface);

    // TODO(ios): Core::Frontend::WindowSystemType has no iOS/Metal enumerator yet.
    // Using Headless as a placeholder keeps this compiling without touching the shared
    // enum (out of scope for this pass); add a real `IOS` or `Metal` value there once a
    // Metal video-core WSI path exists to consume it.
    window_info.type = Core::Frontend::WindowSystemType::Headless;
}
