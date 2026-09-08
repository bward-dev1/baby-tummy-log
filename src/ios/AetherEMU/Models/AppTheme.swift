// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case rail   // vertical side-rail layout (Option 2)
    case dock   // bottom-dock layout (Option 1)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rail: return "Rail"
        case .dock: return "Dock"
        }
    }

    var summary: String {
        switch self {
        case .rail: return "Side navigation, curated shelves, a detail panel next to your library."
        case .dock: return "Full-width carousel with a floating bottom dock."
        }
    }

    var previewGradient: LinearGradient {
        switch self {
        case .rail:
            return LinearGradient(colors: [.purple, .indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dock:
            return LinearGradient(colors: [.pink, .orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
