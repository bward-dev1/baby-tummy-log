// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Shared across every theme (HomeView, DockHomeView, LavaLampHomeView,
/// VerticalLavaLampHomeView, EdenClassicHomeView): wires RailSection/.profile, .recent,
/// and .controller to their real destinations. `.library` and `.settings` stay handled
/// per-view (each already has its own sheet/behavior for those) -- this only covers the
/// three sections that used to select and show nothing.
private struct RailDestinationsModifier: ViewModifier {
    @Binding var rail: RailSection
    let games: [Game]
    let folders: [GameFolder]
    var onPlay: (Game) -> Void

    @State private var isShowingProfile = false
    @State private var isShowingRecent = false
    @State private var isShowingControllers = false

    func body(content: Content) -> some View {
        content
            .onChange(of: rail) { newValue in
                switch newValue {
                case .profile: isShowingProfile = true
                case .recent: isShowingRecent = true
                case .controller: isShowingControllers = true
                default: break
                }
            }
            .sheet(isPresented: $isShowingProfile) {
                ProfileView(games: games, folders: folders, onDismiss: { isShowingProfile = false })
            }
            .sheet(isPresented: $isShowingRecent) {
                RecentlyPlayedView(
                    games: games,
                    onSelect: { game in
                        isShowingRecent = false
                        onPlay(game)
                    },
                    onDismiss: { isShowingRecent = false }
                )
            }
            .sheet(isPresented: $isShowingControllers) {
                ControllersView(onDismiss: { isShowingControllers = false })
            }
    }
}

extension View {
    func railDestinations(
        rail: Binding<RailSection>, games: [Game], folders: [GameFolder], onPlay: @escaping (Game) -> Void
    ) -> some View {
        modifier(RailDestinationsModifier(rail: rail, games: games, folders: folders, onPlay: onPlay))
    }
}
