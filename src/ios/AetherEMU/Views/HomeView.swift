// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct HomeView: View {
    @Binding var games: [Game]
    @Binding var folders: [GameFolder]
    var onPlay: (Game) -> Void
    var onImportTapped: () -> Void
    var onChangeTheme: () -> Void
    var onShowLibrary: () -> Void

    @State private var rail: RailSection = .library
    @State private var selected: Game?
    @State private var isShowingSettings = false

    var body: some View {
        ZStack {
            (selected?.accentGradient ?? Theme.backgroundGradient)
                .opacity(0.5)
                .background(Theme.backgroundGradient)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: selected)

            HStack(alignment: .top, spacing: 16) {
                SideRail(selection: $rail, onImportTapped: onImportTapped, onLibraryTapped: onShowLibrary)

                VStack(spacing: 16) {
                    if let game = selected {
                        GameDetailPanel(game: game, onPlay: { onPlay(game) }, onRemove: { removeGame(game) })
                            .id(game.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        emptyStateHero
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Rail has no folder-browsing view of its own yet (unlike Dock's
                // FolderGrid/FolderDetailSheet) -- but folders is the same @State
                // ContentView shares with Dock, so long-press-to-add here actually
                // does something real: switch to Dock to browse/manage what you added.
                LibraryGrid(games: games, selected: $selected, folders: folders, onAddToFolder: addToFolder)
            }
            .padding(20)

            VStack {
                HStack {
                    Spacer()
                    Button("Change Theme", action: onChangeTheme)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(10)
                }
                Spacer()
            }
        }
        .onChange(of: rail) { newValue in
            switch newValue {
            case .settings: isShowingSettings = true
            case .library: onShowLibrary()
            default: break
            }
        }
        .onChange(of: games) { newValue in
            if selected == nil {
                selected = newValue.first
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

    private func addToFolder(_ game: Game, _ folder: GameFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        if !folders[index].gameIDs.contains(game.id) {
            folders[index].gameIDs.append(game.id)
        }
    }

    private func removeGame(_ game: Game) {
        try? FileManager.default.removeItem(at: game.path)
        games.removeAll { $0.id == game.id }
        for index in folders.indices {
            folders[index].gameIDs.removeAll { $0 == game.id }
        }
        if selected?.id == game.id {
            withAnimation { selected = games.first }
        }
    }

    private var emptyStateHero: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.4))
            Text("No game selected")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            Text("AetherEMU")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }
}
