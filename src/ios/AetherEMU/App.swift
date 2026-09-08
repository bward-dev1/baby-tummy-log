// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

// Phase 0 placeholder SwiftUI entry point.
//
// Not built by CMake (CMake doesn't compile Swift well) -- this file is
// scaffolding for a later phase that wires an actual Xcode app target
// consuming both `aetheremu-ios` (this directory's CMakeLists.txt static
// library) and this Swift source. No .xcodeproj/.xcworkspace exists yet.

import SwiftUI

@main
struct AetherEMUApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("AetherEMU")
    }
}
