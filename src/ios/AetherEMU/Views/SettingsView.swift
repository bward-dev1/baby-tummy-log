// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case about = "About"
    case graphics = "Graphics"
    case controls = "Controls"
    case storage = "Storage"

    var id: String { rawValue }
}

/// Shared two-column settings screen (nav list + detail pane), used by every theme --
/// wired to the .settings icon on SideRail/DockBar that previously did nothing. Content
/// is real AetherEMU concerns (CPU backend status, graphics/controls, import location),
/// not a reproduction of an actual Switch's System Settings category list.
struct SettingsView: View {
    var onDismiss: () -> Void

    @State private var section: SettingsSection = .about

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 0) {
                List(SettingsSection.allCases, selection: $section) { s in
                    Text(s.rawValue).tag(s)
                }
                .listStyle(.plain)
                .frame(width: 200)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch section {
                        case .about:
                            aboutSection
                        case .graphics:
                            graphicsSection
                        case .controls:
                            controlsSection
                        case .storage:
                            storageSection
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AetherEMU").font(.title2.bold())
            Text("An iOS port of the Eden Switch emulator.")
                .foregroundStyle(.secondary)
            Text("See STATUS.md in the repository for a current, honest snapshot of what's implemented.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var graphicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Renderer", value: "Vulkan (MoltenVK)")
            LabeledContent("CPU Backend", value: "Dynarmic (JIT)")
            Text("Dynarmic is currently the only CPU backend available on iOS -- there is no interpreter fallback in this build. JIT support on iOS is unconfirmed; see STATUS.md.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Touch and gamepad input are not wired up yet.")
                .foregroundStyle(.secondary)
            Text("EmuWindow_iOS's touch handlers exist as stubs pending UIKit UITouch forwarding.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Games are imported one at a time via the document picker -- there's no managed game folder yet.")
                .foregroundStyle(.secondary)
        }
    }
}
