// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct FolderDetailSheet: View {
    let folder: GameFolder
    let library: [Game]
    var onPlay: (Game) -> Void
    var onRemove: (Game) -> Void
    var onDismiss: () -> Void

    private var games: [Game] {
        folder.games(in: library)
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if games.isEmpty {
                    Text("No games in this folder yet. Long-press a game in your library to add it here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(games) { game in
                            Button {
                                onPlay(game)
                            } label: {
                                GameTile(game: game, cornerRadius: 12)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    onRemove(game)
                                } label: {
                                    Label("Remove from Folder", systemImage: "folder.badge.minus")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(folder.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }
}
