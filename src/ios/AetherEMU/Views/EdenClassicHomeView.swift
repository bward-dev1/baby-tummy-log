// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The "Classic Eden" theme: evokes desktop Eden's own game-list-first frontend (a
/// toolbar of real actions across the top, a dense sortable list instead of a carousel
/// of cover art, a status bar along the bottom) rather than the mobile-dashboard feel
/// every other theme goes for. Native SwiftUI throughout -- no attempt to reproduce
/// desktop Eden's actual Qt chrome, just the same information-dense, list-first shape,
/// with Aether's own branding.
private enum EdenSortOrder: String, CaseIterable {
    case title = "Title"
    case recent = "Recently Played"
}

struct EdenClassicHomeView: View {
    @Binding var games: [Game]
    @Binding var folders: [GameFolder]
    var onPlay: (Game) -> Void
    var onImportTapped: () -> Void
    var onChangeTheme: () -> Void
    var onShowLibrary: () -> Void

    @State private var rail: RailSection = .library
    @State private var selected: Game?
    @State private var sortOrder: EdenSortOrder = .title
    @State private var isShowingSettings = false

    private var sortedGames: [Game] {
        switch sortOrder {
        case .title:
            return games.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recent:
            return games.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().overlay(Color.white.opacity(0.15))

            if games.isEmpty {
                emptyState
            } else {
                gameList
            }

            Divider().overlay(Color.white.opacity(0.15))

            statusBar
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.13).ignoresSafeArea())
        .onChange(of: rail) { newValue in
            if newValue == .settings {
                isShowingSettings = true
            }
        }
        .onAppear {
            if selected == nil {
                selected = games.first
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(onDismiss: { isShowingSettings = false })
        }
        .railDestinations(rail: $rail, games: games, folders: folders, onPlay: onPlay)
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Text("AetherEMU")
                .font(.headline.bold())
                .foregroundStyle(.white)
                .padding(.trailing, 12)

            ToolbarButton(symbol: "square.and.arrow.down", title: "Import", action: onImportTapped)
            ToolbarButton(symbol: "square.grid.2x2", title: "Library", action: onShowLibrary)
            ToolbarButton(symbol: "person.crop.circle", title: "Profile") { rail = .profile }
            ToolbarButton(symbol: "clock.arrow.circlepath", title: "Recent") { rail = .recent }
            ToolbarButton(symbol: "gamecontroller", title: "Controllers") { rail = .controller }
            ToolbarButton(symbol: "gearshape", title: "Settings") { isShowingSettings = true }

            Spacer()

            Picker("Sort", selection: $sortOrder) {
                ForEach(EdenSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .tint(.white.opacity(0.8))

            ToolbarButton(symbol: "paintpalette", title: "Theme", action: onChangeTheme)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.16, green: 0.16, blue: 0.19))
    }

    private var gameList: some View {
        List(sortedGames, selection: Binding(
            get: { selected?.id },
            set: { id in selected = games.first { $0.id == id } }
        )) { game in
            HStack(spacing: 12) {
                GameTile(game: game, cornerRadius: 4)
                    .frame(width: 32, height: 32 * 4 / 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title)
                        .foregroundStyle(.white)
                    Text(game.path.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text(game.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? "Never played")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Button {
                    onPlay(game)
                } label: {
                    Image(systemName: "play.fill")
                        .padding(6)
                        .background(.white, in: Circle())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(selected?.id == game.id ? Color.white.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { selected = game } }
            .contextMenu {
                Button {
                    onPlay(game)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                if !folders.isEmpty {
                    Menu("Add to Folder") {
                        ForEach(folders) { folder in
                            Button(folder.name) { addToFolder(game, folder) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.2), value: sortOrder)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.4))
            Text("No games imported")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            Button("Import a Game", action: onImportTapped)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text("\(games.count) game\(games.count == 1 ? "" : "s")")
            if !folders.isEmpty {
                Text("\(folders.count) folder\(folders.count == 1 ? "" : "s")")
            }
            Spacer()
            if let selected {
                Text(selected.title)
                    .lineLimit(1)
            }
            Text("Dynarmic (JIT)")
                .foregroundStyle(.white.opacity(0.4))
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.16, green: 0.16, blue: 0.19))
    }

    private func addToFolder(_ game: Game, _ folder: GameFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        if !folders[index].gameIDs.contains(game.id) {
            folders[index].gameIDs.append(game.id)
        }
    }
}

private struct ToolbarButton: View {
    let symbol: String
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                Text(title)
                    .font(.system(size: 9))
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 52)
        }
        .buttonStyle(.plain)
    }
}
