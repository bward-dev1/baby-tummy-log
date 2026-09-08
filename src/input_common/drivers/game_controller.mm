// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

#include "input_common/drivers/game_controller.h"

#import <GameController/GameController.h>
#import <CoreHaptics/CoreHaptics.h>

#include <algorithm>
#include <fmt/format.h>

#include "common/logging/log.h"
#include "common/param_package.h"
#include "common/settings_input.h"
#include "common/uuid.h"

namespace InputCommon {

namespace {
// A fixed guid namespace for every GameController.framework device -- unlike Android, iOS gives
// us no stable per-device VID/PID string, and GCExtendedGamepad already normalizes A/B/X/Y and
// stick layout across vendors, so there is no need to disambiguate by hardware identity here.
// Must be exactly 32 hex chars (Common::UUID's raw-string form) or the FormattedString form --
// this is "AETHERGC" ASCII, hex-encoded and zero-padded to 32 chars.
const Common::UUID GameControllerGuid = Common::UUID{"41455448455247430000000000000000"};
} // namespace

GameController::GameController(std::string input_engine_) : InputEngine(std::move(input_engine_)) {}

GameController::~GameController() {
    Shutdown();
}

void GameController::Init() {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];

    id connect_block = ^(NSNotification* note) {
        GCController* controller = note.object;
        OnControllerConnected((__bridge_retained void*)controller);
    };
    id disconnect_block = ^(NSNotification* note) {
        GCController* controller = note.object;
        OnControllerDisconnected((__bridge void*)controller);
    };

    id connect_token = [center addObserverForName:GCControllerDidConnectNotification
                                            object:nil
                                             queue:[NSOperationQueue mainQueue]
                                        usingBlock:connect_block];
    id disconnect_token = [center addObserverForName:GCControllerDidDisconnectNotification
                                               object:nil
                                                queue:[NSOperationQueue mainQueue]
                                           usingBlock:disconnect_block];
    connect_observer = (__bridge_retained void*)connect_token;
    disconnect_observer = (__bridge_retained void*)disconnect_token;

    // Pick up controllers that connected before Init() ran (e.g. a controller already paired
    // when the app launched).
    for (GCController* controller in [GCController controllers]) {
        OnControllerConnected((__bridge_retained void*)controller);
    }
}

void GameController::Shutdown() {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    if (connect_observer != nullptr) {
        id token = (__bridge_transfer id)connect_observer;
        [center removeObserver:token];
        connect_observer = nullptr;
    }
    if (disconnect_observer != nullptr) {
        id token = (__bridge_transfer id)disconnect_observer;
        [center removeObserver:token];
        disconnect_observer = nullptr;
    }

    for (auto& [port, handle] : connected_controllers) {
        (void)port;
        GCController* controller = (__bridge_transfer GCController*)handle;
        controller.extendedGamepad.valueChangedHandler = nil;
    }
    connected_controllers.clear();

    for (auto& [port, handle] : value_handlers) {
        (void)port;
        // Release the retained block copy; the handler itself was already cleared above.
        id block = (__bridge_transfer id)handle;
        (void)block;
    }
    value_handlers.clear();
}

void GameController::OnControllerConnected(void* gc_controller) {
    GCController* controller = (__bridge GCController*)gc_controller;
    if (controller.extendedGamepad == nil) {
        LOG_WARNING(Input, "Ignoring connected GCController with no extended gamepad profile");
        CFBridgingRelease(gc_controller);
        return;
    }

    const size_t port = next_port++;
    connected_controllers[port] = gc_controller;

    const PadIdentifier identifier = GetIdentifier(port);
    PreSetController(identifier);

    GCExtendedGamepad* __weak weak_gamepad = controller.extendedGamepad;
    GCExtendedGamepadValueChangedHandler handler = ^(GCExtendedGamepad* gamepad,
                                                     GCControllerElement* element) {
        (void)element;
        GCExtendedGamepad* pad = weak_gamepad;
        if (pad == nil) {
            pad = gamepad;
        }

        SetButton(identifier, ButtonA, pad.buttonA.isPressed);
        SetButton(identifier, ButtonB, pad.buttonB.isPressed);
        SetButton(identifier, ButtonX, pad.buttonX.isPressed);
        SetButton(identifier, ButtonY, pad.buttonY.isPressed);
        SetButton(identifier, ButtonL1, pad.leftShoulder.isPressed);
        SetButton(identifier, ButtonR1, pad.rightShoulder.isPressed);
        SetButton(identifier, ButtonL2, pad.leftTrigger.isPressed);
        SetButton(identifier, ButtonR2, pad.rightTrigger.isPressed);
        SetButton(identifier, DpadUp, pad.dpad.up.isPressed);
        SetButton(identifier, DpadDown, pad.dpad.down.isPressed);
        SetButton(identifier, DpadLeft, pad.dpad.left.isPressed);
        SetButton(identifier, DpadRight, pad.dpad.right.isPressed);

        if (pad.leftThumbstickButton != nil) {
            SetButton(identifier, ButtonL3, pad.leftThumbstickButton.isPressed);
        }
        if (pad.rightThumbstickButton != nil) {
            SetButton(identifier, ButtonR3, pad.rightThumbstickButton.isPressed);
        }
        if (pad.buttonMenu != nil) {
            SetButton(identifier, ButtonMenu, pad.buttonMenu.isPressed);
        }
        if (pad.buttonOptions != nil) {
            SetButton(identifier, ButtonOptions, pad.buttonOptions.isPressed);
        }
        if (pad.buttonHome != nil) {
            SetButton(identifier, ButtonHome, pad.buttonHome.isPressed);
        }

        SetAxis(identifier, AXIS_LEFT_X, pad.leftThumbstick.xAxis.value);
        SetAxis(identifier, AXIS_LEFT_Y, pad.leftThumbstick.yAxis.value);
        SetAxis(identifier, AXIS_RIGHT_X, pad.rightThumbstick.xAxis.value);
        SetAxis(identifier, AXIS_RIGHT_Y, pad.rightThumbstick.yAxis.value);
    };

    controller.extendedGamepad.valueChangedHandler = handler;
    value_handlers[port] = (__bridge_retained void*)handler;

    const char* vendor_name = controller.vendorName != nil ? [controller.vendorName UTF8String] : "unknown";
    LOG_INFO(Input, "GameController connected on port {}: {}", port, vendor_name);
}

void GameController::OnControllerDisconnected(void* gc_controller) {
    GCController* controller = (__bridge GCController*)gc_controller;

    size_t found_port = static_cast<size_t>(-1);
    for (const auto& [port, handle] : connected_controllers) {
        if ((__bridge GCController*)handle == controller) {
            found_port = port;
            break;
        }
    }
    if (found_port == static_cast<size_t>(-1)) {
        return;
    }

    controller.extendedGamepad.valueChangedHandler = nil;

    if (auto it = value_handlers.find(found_port); it != value_handlers.end()) {
        id block = (__bridge_transfer id)it->second;
        (void)block;
        value_handlers.erase(it);
    }

    void* retained_handle = connected_controllers[found_port];
    connected_controllers.erase(found_port);
    CFBridgingRelease(retained_handle);

    LOG_INFO(Input, "GameController disconnected from port {}", found_port);
}

Common::Input::DriverResult GameController::SetVibration(
    const PadIdentifier& identifier, const Common::Input::VibrationStatus& vibration) {
    auto it = connected_controllers.find(identifier.port);
    if (it == connected_controllers.end()) {
        return Common::Input::DriverResult::InvalidHandle;
    }

    GCController* controller = (__bridge GCController*)it->second;
    if (@available(iOS 14.0, *)) {
        id<GCDeviceHaptics> haptics = controller.haptics;
        if (haptics == nil) {
            return Common::Input::DriverResult::NotSupported;
        }

        CHHapticEngine* engine = [haptics createEngineWithLocality:GCHapticsLocalityAll];
        if (engine == nil) {
            return Common::Input::DriverResult::NotSupported;
        }

        const float amplitude = std::max(vibration.low_amplitude, vibration.high_amplitude);
        if (amplitude <= 0.0f) {
            [engine stopWithCompletionHandler:nil];
            return Common::Input::DriverResult::Success;
        }

        NSError* error = nil;
        [engine startAndReturnError:&error];
        if (error != nil) {
            return Common::Input::DriverResult::Unknown;
        }

        CHHapticEventParameter* intensity_param =
            [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                                           value:amplitude];
        CHHapticEventParameter* sharpness_param =
            [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness
                                                           value:0.5f];
        CHHapticEvent* event =
            [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
                                           parameters:@[ intensity_param, sharpness_param ]
                                         relativeTime:0
                                             duration:0.1];

        NSError* pattern_error = nil;
        CHHapticPattern* pattern = [[CHHapticPattern alloc] initWithEvents:@[ event ]
                                                                 parameters:@[]
                                                                      error:&pattern_error];
        if (pattern_error != nil || pattern == nil) {
            return Common::Input::DriverResult::Unknown;
        }

        id<CHHapticPatternPlayer> player = [engine createPlayerWithPattern:pattern error:&pattern_error];
        if (pattern_error != nil || player == nil) {
            return Common::Input::DriverResult::Unknown;
        }
        [player startAtTime:0 error:&pattern_error];
        return pattern_error == nil ? Common::Input::DriverResult::Success
                                     : Common::Input::DriverResult::Unknown;
    }
    return Common::Input::DriverResult::NotSupported;
}

bool GameController::IsVibrationEnabled(const PadIdentifier& identifier) {
    auto it = connected_controllers.find(identifier.port);
    if (it == connected_controllers.end()) {
        return false;
    }
    GCController* controller = (__bridge GCController*)it->second;
    if (@available(iOS 14.0, *)) {
        return controller.haptics != nil;
    }
    return false;
}

std::vector<Common::ParamPackage> GameController::GetInputDevices() const {
    std::vector<Common::ParamPackage> devices;
    for (const auto& [port, handle] : connected_controllers) {
        GCController* controller = (__bridge GCController*)handle;
        const std::string name = controller.vendorName != nil
                                     ? std::string([controller.vendorName UTF8String])
                                     : std::string("MFi Controller");
        devices.emplace_back(Common::ParamPackage{
            {"engine", GetEngineName()},
            {"display", fmt::format("{} {}", name, port)},
            {"guid", GameControllerGuid.RawString()},
            {"port", std::to_string(port)},
        });
    }
    return devices;
}

PadIdentifier GameController::GetIdentifier(size_t port) const {
    return {
        .guid = GameControllerGuid,
        .port = port,
        .pad = 0,
    };
}

Common::ParamPackage GameController::BuildAnalogParamPackage(PadIdentifier identifier, int axis_x,
                                                              int axis_y) const {
    Common::ParamPackage params;
    params.Set("engine", GetEngineName());
    params.Set("port", static_cast<int>(identifier.port));
    params.Set("guid", identifier.guid.RawString());
    params.Set("axis_x", axis_x);
    params.Set("axis_y", axis_y);
    params.Set("offset_x", 0);
    params.Set("offset_y", 0);
    params.Set("invert_x", "+");
    params.Set("invert_y", "-");
    return params;
}

Common::ParamPackage GameController::BuildButtonParamPackage(PadIdentifier identifier,
                                                              int button) const {
    Common::ParamPackage params;
    params.Set("engine", GetEngineName());
    params.Set("port", static_cast<int>(identifier.port));
    params.Set("guid", identifier.guid.RawString());
    params.Set("button", button);
    return params;
}

AnalogMapping GameController::GetAnalogMappingForDevice(const Common::ParamPackage& params) {
    if (!params.Has("guid") || !params.Has("port")) {
        return {};
    }
    const PadIdentifier identifier = GetIdentifier(static_cast<size_t>(params.Get("port", 0)));

    AnalogMapping mapping;
    mapping.insert_or_assign(Settings::NativeAnalog::LStick,
                             BuildAnalogParamPackage(identifier, AXIS_LEFT_X, AXIS_LEFT_Y));
    mapping.insert_or_assign(Settings::NativeAnalog::RStick,
                             BuildAnalogParamPackage(identifier, AXIS_RIGHT_X, AXIS_RIGHT_Y));
    return mapping;
}

ButtonMapping GameController::GetButtonMappingForDevice(const Common::ParamPackage& params) {
    if (!params.Has("guid") || !params.Has("port")) {
        return {};
    }
    const PadIdentifier identifier = GetIdentifier(static_cast<size_t>(params.Get("port", 0)));

    ButtonMapping mapping;
    mapping.insert_or_assign(Settings::NativeButton::A, BuildButtonParamPackage(identifier, ButtonA));
    mapping.insert_or_assign(Settings::NativeButton::B, BuildButtonParamPackage(identifier, ButtonB));
    mapping.insert_or_assign(Settings::NativeButton::X, BuildButtonParamPackage(identifier, ButtonX));
    mapping.insert_or_assign(Settings::NativeButton::Y, BuildButtonParamPackage(identifier, ButtonY));
    mapping.insert_or_assign(Settings::NativeButton::L, BuildButtonParamPackage(identifier, ButtonL1));
    mapping.insert_or_assign(Settings::NativeButton::R, BuildButtonParamPackage(identifier, ButtonR1));
    mapping.insert_or_assign(Settings::NativeButton::ZL, BuildButtonParamPackage(identifier, ButtonL2));
    mapping.insert_or_assign(Settings::NativeButton::ZR, BuildButtonParamPackage(identifier, ButtonR2));
    mapping.insert_or_assign(Settings::NativeButton::LStick,
                             BuildButtonParamPackage(identifier, ButtonL3));
    mapping.insert_or_assign(Settings::NativeButton::RStick,
                             BuildButtonParamPackage(identifier, ButtonR3));
    mapping.insert_or_assign(Settings::NativeButton::Plus,
                             BuildButtonParamPackage(identifier, ButtonMenu));
    mapping.insert_or_assign(Settings::NativeButton::Minus,
                             BuildButtonParamPackage(identifier, ButtonOptions));
    mapping.insert_or_assign(Settings::NativeButton::Home,
                             BuildButtonParamPackage(identifier, ButtonHome));
    mapping.insert_or_assign(Settings::NativeButton::DUp, BuildButtonParamPackage(identifier, DpadUp));
    mapping.insert_or_assign(Settings::NativeButton::DDown,
                             BuildButtonParamPackage(identifier, DpadDown));
    mapping.insert_or_assign(Settings::NativeButton::DLeft,
                             BuildButtonParamPackage(identifier, DpadLeft));
    mapping.insert_or_assign(Settings::NativeButton::DRight,
                             BuildButtonParamPackage(identifier, DpadRight));
    return mapping;
}

Common::Input::ButtonNames GameController::GetUIName(
    [[maybe_unused]] const Common::ParamPackage& params) const {
    return Common::Input::ButtonNames::Value;
}

} // namespace InputCommon
