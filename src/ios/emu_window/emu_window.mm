// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#include "ios/emu_window/emu_window.h"

#include "common/logging.h"
#include "input_common/drivers/touch_screen.h"
#include "input_common/main.h"
#include "ios/native.h"
#import "ios/native_surface.h"

// Wires window_info.render_surface/type for the Vulkan Metal-surface WSI path
// (video_core/vulkan_common/vulkan_surface.cpp's CreateSurface, vulkan_instance.cpp's
// RequiredExtensions -- both branch on WindowSystemType::Cocoa, which is Apple's shared
// macOS/iOS WSI enumerator, not a Cocoa-specific one; there is no separate iOS value and
// none is needed). UNTESTED: no local Xcode/iOS SDK/device exists to compile or run this
// -- the __bridge cast below, CAMetalLayer.drawableSize's value at the time
// attachMetalLayer runs (MetalView.swift sets drawableSize just before calling in), and
// whether vkCreateMetalSurfaceEXT actually succeeds against whatever Vulkan-on-Metal ICD
// AetherEMU links on iOS are all unverified until CI is unblocked.
void EmuWindow_iOS::OnSurfaceChanged(AetherNativeSurface* surface) {
    if (!surface || !surface->layer) {
        LOG_INFO(Frontend, "EmuWindow_iOS::OnSurfaceChanged received null surface");
        m_window_width = 0;
        m_window_height = 0;
        window_info.render_surface = nullptr;
        window_info.type = Core::Frontend::WindowSystemType::Headless;
        return;
    }

    CAMetalLayer* layer = surface->layer;
    m_window_width = static_cast<float>(layer.drawableSize.width);
    m_window_height = static_cast<float>(layer.drawableSize.height);

    UpdateCurrentFramebufferLayout(static_cast<u32>(m_window_width),
                                    static_cast<u32>(m_window_height));

    // vulkan_surface.cpp's CreateSurface casts render_surface straight to
    // `const CAMetalLayer*` -- store the raw layer pointer, not the wrapper struct.
    // `__bridge` because render_surface is a plain void* with no ownership of its own;
    // AetherNativeSurface::layer (see AetherBridge.mm) already keeps the strong ARC ref
    // alive for as long as the surface is attached.
    window_info.render_surface = (__bridge void*)layer;
    window_info.type = Core::Frontend::WindowSystemType::Cocoa;
}

// Called from AetherBridge.mm's touchPressed:/Moved:/Released:, which MetalHostView
// (MetalView.swift) forwards real UITouch events into -- UNVERIFIED, no device/CI
// result exists yet to confirm the coordinate space actually lines up correctly.
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

// TODO(ios): calls OnEmulationStarted() directly on the first frame -- fine since there's
// no JNI-fiber-hop equivalent needed here, but this runs on whatever thread the GPU/video
// thread calls OnFrameDisplayed from, not necessarily the main thread. If anything this
// triggers ever needs to touch UIKit, it will need an explicit dispatch to the main queue.
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

    // OnSurfaceChanged above sets window_info.type/render_surface for both the success
    // and null-surface cases -- nothing further to set here.
    OnSurfaceChanged(surface);
}
