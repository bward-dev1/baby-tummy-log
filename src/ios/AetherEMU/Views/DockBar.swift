// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Horizontal counterpart to SideRail -- same RailSection actions, laid out as a
/// floating bottom dock instead of a vertical side strip. Used by the Dock theme.
struct DockBar: View {
    @Binding var selection: RailSection
    var onImportTapped: () -> Void
    var onLibraryTapped: () -> Void = {}

    var body: some View {
        HStack(spacing: 18) {
            ForEach(RailSection.allCases) { section in
                Button {
                    switch section {
                    case .importGame:
                        onImportTapped()
                    case .library:
                        selection = section
                        onLibraryTapped()
                    default:
                        selection = section
                    }
                } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(selection == section ? .white : .white.opacity(0.55))
                        .background(
                            Circle()
                                .fill(selection == section ? Color.white.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 32)
    }
}
