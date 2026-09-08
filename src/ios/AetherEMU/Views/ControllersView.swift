// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import GameController

/// Wired to RailSection/.controller, which used to select and render nothing real.
/// Reads live GCController state directly (no dependency on InputCommon::GameController
/// -- that's the C++-side driver forwarding input into the emulator, this is purely
/// "what does iOS itself currently see plugged in", which is real and independently
/// useful for confirming a controller actually paired before loading a game).
struct ControllersView: View {
    var onDismiss: () -> Void

    @State private var controllers: [GCController] = GCController.controllers()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if controllers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No controller connected")
                                .foregroundStyle(.secondary)
                            Text("Pair an MFi, PlayStation, or Xbox controller in iOS Settings > Bluetooth, or connect one over USB-C.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(controllers, id: \.self) { controller in
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(controller.vendorName ?? "Unknown Controller")
                                    Text(controller.extendedGamepad != nil ? "Extended gamepad" : "Basic gamepad")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Connected Controllers")
                }

                Section {
                    Text("Every connected controller forwards buttons, sticks, and (on iOS 14+) haptic feedback into the emulator via InputCommon::GameController. There's no per-game remapping UI yet -- controllers use the driver's default Switch Pro-style mapping.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("How This Works")
                }
            }
            .navigationTitle("Controllers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
            .onAppear { controllers = GCController.controllers() }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
                withAnimation { controllers = GCController.controllers() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
                withAnimation { controllers = GCController.controllers() }
            }
        }
    }
}
