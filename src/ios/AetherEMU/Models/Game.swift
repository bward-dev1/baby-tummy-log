// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A game the user has imported (NSP/XCI/NCA). AetherEMU doesn't fetch box art over the
/// network -- no metadata service is wired up, and shipping copyrighted cover art
/// wouldn't be ours to bundle anyway -- so `accentHue` deterministically derives a
/// per-game gradient from the title instead. Looks intentional, costs nothing, needs no
/// network access at all.
struct Game: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let path: URL
    var lastPlayed: Date?

    init(title: String, path: URL, lastPlayed: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.path = path
        self.lastPlayed = lastPlayed
    }

    var accentHue: Double {
        let hash = title.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
        return Double(hash % 360) / 360.0
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: accentHue, saturation: 0.55, brightness: 0.85),
                Color(hue: (accentHue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.55),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
