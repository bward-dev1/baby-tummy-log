// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Shared implementation for the two Vertical Lava Lamp themes -- a scrollable
/// single-column list (portrait-friendly) over an animated blob background, distinct
/// from LavaLampHomeView's horizontal carousel.
struct VerticalLavaLampHomeView: View {
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

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
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
                .padding(20)

                if games.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Import a game to get started")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(games) { game in
                                Button {
                                    selected = game
                                } label: {
                                    HStack(spacing: 14) {
                                        GameTile(game: game, isSelected: selected?.id == game.id, cornerRadius: 12)
                                            .frame(width: 64, height: 85)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(game.title)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.white)
                                            Text(game.path.lastPathComponent)
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                        Spacer()
                                        if selected?.id == game.id {
                                            Button {
                                                onPlay(game)
                                            } label: {
                                                Image(systemName: "play.fill")
                                                    .padding(10)
                                                    .background(.white, in: Circle())
                                                    .foregroundStyle(.black)
                                            }
                                            .buttonStyle(.plain)
                                            .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                    .padding(10)
                                    .glassCard(cornerRadius: 16)
                                }
                                .buttonStyle(.plain)
                                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }
                }
            }

            VStack {
                Spacer()
                DockBar(selection: $rail, onImportTapped: onImportTapped, onLibraryTapped: onShowLibrary)
                    .padding(.bottom, 20)
            }
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
