// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum Theme {
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.09, blue: 0.20),
            Color(red: 0.20, green: 0.11, blue: 0.28),
            Color(red: 0.12, green: 0.14, blue: 0.24),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let railBackground = Color.white.opacity(0.06)
    static let cardBackground = Color.white.opacity(0.08)
    static let cardBorder = Color.white.opacity(0.12)
}

/// The frosted-glass card look used throughout the home screen (rail, hero panel, grid
/// panel). Centralized so every surface reads as one consistent material rather than
/// several near-identical hand-tuned blurs.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
