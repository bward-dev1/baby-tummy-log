// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
struct AetherEMUApp: App {
    init() {
        // Must happen before anything else touches AetherBridge -- points the engine's
        // EdenPath machinery (keys/firmware/NAND/saves/logs) at a real writable sandbox
        // directory and starts the logging system. Previously nothing on iOS ever called
        // the C++-side equivalent at all, so every engine log line went nowhere.
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        AetherBridge.shared().initializeApplication(support.path)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
        }
    }
}
