// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct GameTile: View {
    let game: Game
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(game.accentGradient)
            .overlay(alignment: .bottomLeading) {
                Text(game.title)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(8)
                    .shadow(color: .black.opacity(0.5), radius: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? .white : .white.opacity(0.15), lineWidth: isSelected ? 3 : 1)
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }
}
