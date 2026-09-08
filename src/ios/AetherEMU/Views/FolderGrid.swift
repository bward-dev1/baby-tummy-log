// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct FolderTile: View {
    let folder: GameFolder
    let library: [Game]

    private var previewGames: [Game] {
        Array(folder.games(in: library).prefix(4))
    }

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    if index < previewGames.count {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(previewGames[index].accentGradient)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
            }
            .padding(8)
            .aspectRatio(1, contentMode: .fit)
            .glassCard(cornerRadius: 16)

            Text(folder.name)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

struct NewFolderTile: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .glassCard(cornerRadius: 16)

            Text("New Folder")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct FolderGrid: View {
    let folders: [GameFolder]
    let library: [Game]
    var onCreate: () -> Void
    var onOpen: (GameFolder) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                Button(action: onCreate) {
                    NewFolderTile()
                }
                .buttonStyle(.plain)

                ForEach(folders) { folder in
                    Button {
                        onOpen(folder)
                    } label: {
                        FolderTile(folder: folder, library: library)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
