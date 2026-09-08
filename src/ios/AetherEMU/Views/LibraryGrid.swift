// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct LibraryGrid: View {
    let games: [Game]
    @Binding var selected: Game?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Library")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text("\(games.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            if games.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Import a game to get started")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(games) { game in
                            Button {
                                selected = game
                            } label: {
                                GameTile(game: game, isSelected: selected?.id == game.id, cornerRadius: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 220)
        .glassCard()
    }
}
