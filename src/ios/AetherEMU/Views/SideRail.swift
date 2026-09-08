// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum RailSection: String, CaseIterable, Identifiable {
    case profile, library, importGame, recent, controller, settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .profile: return "person.crop.circle.fill"
        case .library: return "square.grid.2x2.fill"
        case .importGame: return "square.and.arrow.down.fill"
        case .recent: return "clock.arrow.circlepath"
        case .controller: return "gamecontroller.fill"
        case .settings: return "gearshape.fill"
        }
    }

    // Every case here now opens a real screen -- see ProfileView, RecentlyPlayedView,
    // ControllersView, and SettingsView. `.captures` (screenshot capture) used to be a
    // selectable no-op since nothing in the engine/bridge can capture a frame; replaced
    // with `.recent`, which is real and backed by GameLibrary's own lastPlayed data.
}

struct SideRail: View {
    @Binding var selection: RailSection
    var onImportTapped: () -> Void
    var onLibraryTapped: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            ForEach(RailSection.allCases) { section in
                Button {
                    switch section {
                    case .importGame:
                        onImportTapped()
                    case .library:
                        // Always fires, even when .library is already the current
                        // selection (it's the default -- .onChange-based routing
                        // elsewhere wouldn't see a change on the very first tap).
                        selection = section
                        onLibraryTapped()
                    default:
                        selection = section
                    }
                } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(selection == section ? .white : .white.opacity(0.55))
                        .scaleEffect(selection == section ? 1.08 : 1.0)
                        .background(
                            Circle()
                                .fill(selection == section ? Color.white.opacity(0.18) : Color.clear)
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 20)
        .frame(width: 72)
        .glassCard(cornerRadius: 28)
    }
}
