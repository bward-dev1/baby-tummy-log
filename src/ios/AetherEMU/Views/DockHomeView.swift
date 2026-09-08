// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

private enum DockBrowseMode: String, CaseIterable {
    case library = "Library"
    case folders = "Folders"
}

/// The "Dock" theme: a full-width horizontal carousel with a floating bottom dock,
/// a Library/Folders toggle, and a "View More" detail sheet -- in the spirit of the
/// bottom-dock reference concepts, but with its own wording throughout (no "View All"
/// header text copied verbatim, no A/X button-hint glyphs, no real person's likeness)
/// rather than reproducing that concept's on-screen text/imagery, since it leans much
/// closer to a literal recreation of Nintendo's own system menu than the Rail theme
/// does. Folders here are genuinely user-organized (long-press a game to add it to
/// one) -- AetherEMU has no metadata service to back curated genre shelves.
struct DockHomeView: View {
    @Binding var games: [Game]
    @Binding var folders: [GameFolder]
    var onPlay: (Game) -> Void
    var onImportTapped: () -> Void
    var onChangeTheme: () -> Void

    @State private var rail: RailSection = .library
    @State private var selected: Game?
    @State private var mode: DockBrowseMode = .library
    @State private var openFolder: GameFolder?
    @State private var isShowingDetail = false
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isShowingSettings = false

    var body: some View {
        ZStack {
            (selected?.accentGradient ?? Theme.backgroundGradient)
                .opacity(0.5)
                .background(Theme.backgroundGradient)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: selected)

            VStack(spacing: 16) {
                HStack {
                    Text("AetherEMU")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Change Theme", action: onChangeTheme)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Picker("", selection: $mode) {
                            ForEach(DockBrowseMode.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        Spacer()
                        Text(mode == .library ? "\(games.count) games" : "\(folders.count) folders")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    if mode == .folders {
                        FolderGrid(
                            folders: folders,
                            library: games,
                            onCreate: { isCreatingFolder = true },
                            onOpen: { openFolder = $0 }
                        )
                        .frame(minHeight: 260)
                    } else if games.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.4))
                            Text("Import a game to get started")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(games) { game in
                                    Button {
                                        selected = game
                                    } label: {
                                        VStack {
                                            GameTile(game: game, isSelected: selected?.id == game.id)
                                                .overlay(alignment: .topLeading) {
                                                    if selected?.id == game.id {
                                                        Text("Now Viewing")
                                                            .font(.caption2.bold())
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 3)
                                                            .background(.white, in: Capsule())
                                                            .foregroundStyle(.black)
                                                            .padding(8)
                                                    }
                                                }
                                        }
                                        .frame(width: 160)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if folders.isEmpty {
                                            Text("No folders yet")
                                        } else {
                                            ForEach(folders) { folder in
                                                Button {
                                                    addGame(game, to: folder)
                                                } label: {
                                                    Label(folder.name, systemImage: "folder")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if mode == .library, let game = selected {
                        Divider().overlay(.white.opacity(0.15))
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title)
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                Text(game.path.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Button("View More") {
                                isShowingDetail = true
                            }
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            Button {
                                onPlay(game)
                            } label: {
                                Label("Open", systemImage: "play.fill")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(.white, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .glassCard()

                Spacer()

                DockBar(selection: $rail, onImportTapped: onImportTapped)
            }
            .padding(20)
        }
        .onChange(of: rail) { newValue in
            if newValue == .settings {
                isShowingSettings = true
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
        .sheet(isPresented: $isShowingDetail) {
            if let game = selected {
                GameDetailPanel(game: game, onPlay: { onPlay(game); isShowingDetail = false })
                    .padding()
                    .background(Theme.backgroundGradient)
            }
        }
        .sheet(item: $openFolder) { folder in
            FolderDetailSheet(
                folder: folder,
                library: games,
                onPlay: { game in onPlay(game); openFolder = nil },
                onRemove: { game in removeGame(game, from: folder) },
                onDismiss: { openFolder = nil }
            )
        }
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    folders.append(GameFolder(name: name))
                }
                newFolderName = ""
            }
        }
    }

    private func addGame(_ game: Game, to folder: GameFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        if !folders[index].gameIDs.contains(game.id) {
            folders[index].gameIDs.append(game.id)
        }
    }

    private func removeGame(_ game: Game, from folder: GameFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].gameIDs.removeAll { $0 == game.id }
        openFolder = folders[index]
    }
}
