// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A dedicated full-screen game grid, shared across all eight themes and wired to the
/// .library rail/dock icon (previously a dead visual-only selection everywhere except
/// as an implicit default). Distinct from each theme's inline carousel/list -- this is
/// the "see everything at once" view.
struct LibraryPageView: View {
    let games: [Game]
    var onSelect: (Game) -> Void
    var onDismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if games.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("Import a game to get started")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(games) { game in
                            Button {
                                onSelect(game)
                            } label: {
                                GameTile(game: game, cornerRadius: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }
}
