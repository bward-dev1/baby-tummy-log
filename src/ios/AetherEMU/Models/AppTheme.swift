// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case rail       // vertical side-rail layout
    case dock       // bottom-dock layout with Folders
    case lavaWarm   // full-width carousel, warm pink/orange/magenta lava-lamp background
    case lavaCool   // full-width carousel, cool blue/teal/purple lava-lamp background

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rail: return "Rail"
        case .dock: return "Dock"
        case .lavaWarm: return "Lava Lamp — Warm"
        case .lavaCool: return "Lava Lamp — Cool"
        }
    }

    var summary: String {
        switch self {
        case .rail: return "Side navigation, curated shelves, a detail panel next to your library."
        case .dock: return "Full-width carousel with a floating bottom dock and Folders."
        case .lavaWarm: return "Soft floating color blobs over a warm pink/orange gradient."
        case .lavaCool: return "Soft floating color blobs over a cool blue/teal gradient."
        }
    }

    var previewGradient: LinearGradient {
        switch self {
        case .rail:
            return LinearGradient(colors: [.purple, .indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dock:
            return LinearGradient(colors: [.pink, .orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lavaWarm:
            return LinearGradient(colors: [Color(red: 0.93, green: 0.29, blue: 0.55), Color(red: 0.98, green: 0.55, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lavaCool:
            return LinearGradient(colors: [Color(red: 0.29, green: 0.55, blue: 0.93), Color(red: 0.25, green: 0.85, blue: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
