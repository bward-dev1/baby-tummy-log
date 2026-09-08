// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Shared implementation for both Lava Lamp themes (warm/cool) -- a full-width
/// horizontal carousel over an animated blob background, with a floating bottom dock.
/// Simpler than Dock (no Folders): a straightforward carousel + selected-title + dock,
/// matching the reference layout's shape but with its own wording, not literal
/// Nintendo system-menu text.
struct LavaLampHomeView: View {
    let palette: LavaLampPalette
    @Binding var games: [Game]
    var onPlay: (Game) -> Void
    var onImportTapped: () -> Void
    var onChangeTheme: () -> Void
    var onShowLibrary: () -> Void

    @State private var rail: RailSection = .library
    @State private var selected: Game?
    @State private var isShowingSettings = false

    var body: some View {
        ZStack {
            LavaLampBackground(palette: palette)

            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    VStack(spacing: 0) {
                        Text("AETHER")
                            .font(.caption.weight(.semibold))
                            .tracking(4)
                        Text("EMU")
                            .font(.title2.bold())
                    }
                    .foregroundStyle(.white)
                    Spacer()
                    Button("Change Theme", action: onChangeTheme)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Library")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    Divider().overlay(.white.opacity(0.2))

                    if games.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.6))
                            Text("Import a game to get started")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(games) { game in
                                    Button {
                                        selected = game
                                    } label: {
                                        GameTile(game: game, isSelected: selected?.id == game.id)
                                            .frame(width: 140)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if let game = selected {
                            Text(game.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .id(game.id)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(20)
                .glassCard()
                .animation(.easeInOut(duration: 0.2), value: selected)

                Spacer()

                HStack {
                    DockBar(selection: $rail, onImportTapped: onImportTapped, onLibraryTapped: onShowLibrary)
                    if let game = selected {
                        Button {
                            onPlay(game)
                        } label: {
                            Label("Open", systemImage: "play.fill")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(.white, in: Capsule())
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
        .railDestinations(rail: $rail, games: games, folders: [], onPlay: onPlay)
    }
}
