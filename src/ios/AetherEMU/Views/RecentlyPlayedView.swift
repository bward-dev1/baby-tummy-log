// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Replaces the old RailSection/.captures slot (screenshot capture isn't implemented
/// anywhere in the engine or bridge -- building it would mean inventing a fake button,
/// which is exactly what this pass is fixing, not repeating). This is a real feature
/// backed entirely by GameLibrary's own `lastPlayed` data.
struct RecentlyPlayedView: View {
    let games: [Game]
    var onSelect: (Game) -> Void
    var onDismiss: () -> Void

    private var recent: [Game] {
        games.filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recent.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("Nothing played yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(recent) { game in
                        Button {
                            onSelect(game)
                        } label: {
                            HStack(spacing: 14) {
                                GameTile(game: game, cornerRadius: 10)
                                    .frame(width: 48, height: 64)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(game.title)
                                    Text(game.lastPlayed?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Recently Played")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }
}
