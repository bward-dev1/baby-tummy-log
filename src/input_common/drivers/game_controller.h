// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "input_common/input_engine.h"

namespace InputCommon {

/**
 * iOS/iPadOS MFi and PS/Xbox controller backend, backed by Apple's GameController.framework.
 *
 * The header stays plain C++ (no Objective-C types) so that main.cpp -- which is compiled as
 * ordinary C++, not Objective-C++, even on iOS -- can include it. All GCController/GCExtendedGamepad
 * interaction lives in game_controller.mm; controller handles cross the boundary as CFBridgingRetain'd
 * `void*`, the same pattern native_surface.h/AetherBridge.mm already use for CAMetalLayer.
 */
class GameController final : public InputEngine {
public:
    explicit GameController(std::string input_engine_);
    ~GameController() override;

    /// Registers for GCControllerDidConnect/DidDisconnect notifications and picks up any
    /// controller that connected before this ran.
    void Init();

    /// Unregisters notifications and releases all retained controller/observer handles.
    void Shutdown();

    Common::Input::DriverResult SetVibration(
        const PadIdentifier& identifier, const Common::Input::VibrationStatus& vibration) override;

    bool IsVibrationEnabled(const PadIdentifier& identifier) override;

    std::vector<Common::ParamPackage> GetInputDevices() const override;

    AnalogMapping GetAnalogMappingForDevice(const Common::ParamPackage& params) override;

    ButtonMapping GetButtonMappingForDevice(const Common::ParamPackage& params) override;

    Common::Input::ButtonNames GetUIName(const Common::ParamPackage& params) const override;

    /// Called from the Objective-C connect notification handler.
    /// @param gc_controller A CFBridgingRetain'd GCController*; ownership transfers to this class.
    void OnControllerConnected(void* gc_controller);

    /// Called from the Objective-C disconnect notification handler.
    /// @param gc_controller The same GCController* pointer previously passed to
    /// OnControllerConnected (compared by identity, not retained again).
    void OnControllerDisconnected(void* gc_controller);

private:
    PadIdentifier GetIdentifier(size_t port) const;

    Common::ParamPackage BuildAnalogParamPackage(PadIdentifier identifier, int axis_x,
                                                 int axis_y) const;
    Common::ParamPackage BuildButtonParamPackage(PadIdentifier identifier, int button) const;

    // Axis indices used internally for BuildAnalogParamPackage; arbitrary but stable identifiers,
    // not raw HID usages (GameController.framework normalizes across vendors already).
    static constexpr int AXIS_LEFT_X = 0;
    static constexpr int AXIS_LEFT_Y = 1;
    static constexpr int AXIS_RIGHT_X = 2;
    static constexpr int AXIS_RIGHT_Y = 3;

    // Button indices used internally, one per GCExtendedGamepad element this driver reads.
    enum ButtonId : int {
        ButtonA = 0,
        ButtonB,
        ButtonX,
        ButtonY,
        ButtonL1,
        ButtonR1,
        ButtonL2,
        ButtonR2,
        ButtonL3,
        ButtonR3,
        ButtonMenu,
        ButtonOptions,
        ButtonHome,
        DpadUp,
        DpadDown,
        DpadLeft,
        DpadRight,
    };

    // GCController* handles, CFBridgingRetain'd, keyed by assigned port.
    ::Common::unordered_map<size_t, void*> connected_controllers;
    // The per-controller valueChangedHandler block, CFBridgingRetain'd, keyed by port -- kept
    // alive here since GCExtendedGamepad only holds a weak/copy reference while set.
    ::Common::unordered_map<size_t, void*> value_handlers;

    size_t next_port{0};
    // NSObject<NSObject>* notification tokens, CFBridgingRetain'd.
    void* connect_observer{nullptr};
    void* disconnect_observer{nullptr};
};

} // namespace InputCommon
