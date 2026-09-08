// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum RailSection: String, CaseIterable, Identifiable {
    case profile, library, importGame, captures, controller, settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .profile: return "person.crop.circle.fill"
        case .library: return "square.grid.2x2.fill"
        case .importGame: return "square.and.arrow.down.fill"
        case .captures: return "photo.stack.fill"
        case .controller: return "gamecontroller.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// Only `.library` and `.importGame` are wired to real behavior today (see
    /// HomeView). The rest render and select like real nav items -- consistent with
    /// this codebase's existing honest-stub convention (native.h/emu_window.h's
    /// TODO(ios) comments) -- rather than being hidden, so the layout reads as finished
    /// even though the destinations aren't built yet.
    var isImplemented: Bool {
        switch self {
        case .library, .importGame: return true
        case .profile, .captures, .controller, .settings: return false
        }
    }
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
                        .background(
                            Circle()
                                .fill(selection == section ? Color.white.opacity(0.18) : Color.clear)
                        )
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
