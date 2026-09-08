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

// TODO(ios): This is a placeholder for the native surface type the Metal bridge will
// hand off (e.g. a CAMetalLayer* pulled out of a CAMetalLayer-backed UIView/MTKView).
// Forward-declared as an opaque pointer so this header has zero Objective-C dependency
// and can be included from plain C++ translation units.
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

// TODO(ios): This mirrors EmuWindow_Android's shape but is currently an unimplemented
// stub -- it exists so the iOS bridge target has something concrete to compile/link
// against ahead of an actual Xcode app target and Metal-backed view. None of the
// surface/frame-rate-hint logic below is real yet.
class EmuWindow_iOS final : public Core::Frontend::EmuWindow {

public:
    EmuWindow_iOS(AetherNativeSurface* surface,
                  std::shared_ptr<Common::DynamicLibrary> driver_library);

    ~EmuWindow_iOS() = default;

    // TODO(ios): Called when the app hands us a new/updated CAMetalLayer (e.g. on
    // view resize, or after a scene reconnects following backgrounding).
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
