// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case rail              // vertical side-rail layout
    case dock              // bottom-dock layout with Folders
    case lavaWarm          // full-width carousel, warm pink/orange/magenta lava-lamp background
    case lavaCool          // full-width carousel, cool blue/teal/purple lava-lamp background
    case lavaVerticalRed   // vertical list layout, coral/rose/magenta lava-lamp background
    case lavaVerticalBlue  // vertical list layout, periwinkle/teal/violet lava-lamp background
    case lavaDark          // full-width carousel, near-black charcoal lava-lamp background
    case lavaVerticalDark  // vertical list layout, near-black charcoal lava-lamp background

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rail: return "Rail"
        case .dock: return "Dock"
        case .lavaWarm: return "Lava Lamp — Warm"
        case .lavaCool: return "Lava Lamp — Cool"
        case .lavaVerticalRed: return "Lava Lamp — Vertical Red"
        case .lavaVerticalBlue: return "Lava Lamp — Vertical Blue"
        case .lavaDark: return "Lava Lamp — Dark"
        case .lavaVerticalDark: return "Lava Lamp — Vertical Dark"
        }
    }

    var summary: String {
        switch self {
        case .rail: return "Side navigation, curated shelves, a detail panel next to your library."
        case .dock: return "Full-width carousel with a floating bottom dock and Folders."
        case .lavaWarm: return "Soft floating color blobs over a warm pink/orange gradient."
        case .lavaCool: return "Soft floating color blobs over a cool blue/teal gradient."
        case .lavaVerticalRed: return "A scrollable vertical list over a coral/rose/magenta gradient."
        case .lavaVerticalBlue: return "A scrollable vertical list over a periwinkle/teal/violet gradient."
        case .lavaDark: return "Full-width carousel over a low-contrast charcoal gradient."
        case .lavaVerticalDark: return "A scrollable vertical list over a low-contrast charcoal gradient."
        }
    }

    var previewGradient: LinearGradient {
        switch self {
        case .rail:
            return LinearGradient(colors: [.purple, .indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dock:
            return LinearGradient(colors: [.pink, .orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lavaWarm:
            return LavaLampPalette.warm.base
        case .lavaCool:
            return LavaLampPalette.cool.base
        case .lavaVerticalRed:
            return LavaLampPalette.verticalRed.base
        case .lavaVerticalBlue:
            return LavaLampPalette.verticalBlue.base
        case .lavaDark, .lavaVerticalDark:
            return LavaLampPalette.dark.base
        }
    }
}
