// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Wired to RailSection/.profile, which used to select and render nothing real. Every
/// number here is computed from the real GameLibrary/AetherBridge state -- no invented
/// account/friends-list concept, since AetherEMU has no backend to back one.
struct ProfileView: View {
    let games: [Game]
    let folders: [GameFolder]
    var onDismiss: () -> Void

    private var storageUsedBytes: Int64 {
        games.reduce(Int64(0)) { total, game in
            let size = (try? FileManager.default.attributesOfItem(atPath: game.path.path)[.size] as? Int64) ?? 0
            return total + size
        }
    }

    private var storageUsedFormatted: String {
        ByteCountFormatter.string(fromByteCount: storageUsedBytes, countStyle: .file)
    }

    private var keysInstalled: Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileManager.default.fileExists(atPath: support.appendingPathComponent("keys/prod.keys").path)
    }

    private var mostRecentlyPlayed: Game? {
        games.filter { $0.lastPlayed != nil }.max { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.85))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your Library")
                                .font(.title2.bold())
                            Text(mostRecentlyPlayed.map { "Last played \($0.title)" } ?? "No games played yet")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatTile(title: "Games", value: "\(games.count)", symbol: "square.grid.2x2.fill")
                        StatTile(title: "Folders", value: "\(folders.count)", symbol: "folder.fill")
                        StatTile(title: "Storage Used", value: storageUsedFormatted, symbol: "internaldrive.fill")
                        StatTile(title: "Keys", value: keysInstalled ? "Installed" : "Missing",
                                 symbol: keysInstalled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                                 tint: keysInstalled ? .green : .orange)
                    }

                    if !games.isEmpty {
                        Text("Play Time by Recency")
                            .font(.subheadline.bold())
                        VStack(spacing: 0) {
                            ForEach(games.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }.prefix(6)) { game in
                                HStack {
                                    Text(game.title).lineLimit(1)
                                    Spacer()
                                    Text(game.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
