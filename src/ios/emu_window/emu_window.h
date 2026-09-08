// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <chrono>
#include <cstdint>
#include <memory>

#include "core/frontend/emu_window.h"
#include "core/frontend/graphics_context.h"
#include "input_common/main.h"

// Real definition lives in ios/native_surface.h (an ObjC++ header, included only from
// .mm files -- AetherBridge.mm and emu_window.mm). Forward-declared as an opaque type
// here so this header has zero Objective-C dependency and can be included from plain
// C++ translation units.
struct AetherNativeSurface;

class GraphicsContext_iOS final : public Core::Frontend::GraphicsContext {
public:
    explicit GraphicsContext_iOS(std::shared_ptr<Common::DynamicLibrary> driver_library)
        : m_driver_library{driver_library} {}

    ~GraphicsContext_iOS() = default;

    std::shared_ptr<Common::DynamicLibrary> GetDriverLibrary() override {
        return m_driver_library;
    }

private:
    std::shared_ptr<Common::DynamicLibrary> m_driver_library;
};

// TODO(ios): This mirrors EmuWindow_Android's shape. OnSurfaceChanged now wires a real
// CAMetalLayer through to window_info (WindowSystemType::Cocoa + the raw layer pointer,
// see emu_window.mm) so video_core's Vulkan CreateSurface has what it needs -- but this
// is UNVERIFIED, no local Xcode/iOS SDK/device exists to compile or run it against CI.
// Touch input (OnTouchPressed/Moved/Released below) and frame-rate hints are still not
// wired to any real UIKit event source -- there's no app target/view hierarchy yet.
class EmuWindow_iOS final : public Core::Frontend::EmuWindow {

public:
    EmuWindow_iOS(AetherNativeSurface* surface,
                  std::shared_ptr<Common::DynamicLibrary> driver_library);

    ~EmuWindow_iOS() = default;

    // Called when the app hands us a new/updated CAMetalLayer (e.g. on view resize, or
    // after a scene reconnects following backgrounding). Sets window_info.render_surface
    // (the raw CAMetalLayer*, __bridge void*) and window_info.type -- see emu_window.mm.
    void OnSurfaceChanged(AetherNativeSurface* surface);
    void OnFrameDisplayed() override;

    // TODO(ios): Wire these up to UIKit touch/pencil event forwarding once there's an
    // app target to receive UITouch events from.
    void OnTouchPressed(int id, float x, float y);
    void OnTouchMoved(int id, float x, float y);
    void OnTouchReleased(int id);

    std::unique_ptr<Core::Frontend::GraphicsContext> CreateSharedContext() const override {
        return {std::make_unique<GraphicsContext_iOS>(m_driver_library)};
    }
    bool IsShown() const override {
        return true;
    };

private:
    using Clock = std::chrono::steady_clock;

    float m_window_width{};
    float m_window_height{};

    std::shared_ptr<Common::DynamicLibrary> m_driver_library;

    bool m_first_frame = false;
};
