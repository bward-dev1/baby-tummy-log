// SPDX-FileCopyrightText: Copyright 2026 AetherEMU Project
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

private enum SettingsSection: String, CaseIterable, Identifiable {
    case about = "About"
    case systemFiles = "Keys & Firmware"
    case graphics = "Graphics"
    case controls = "Controls"
    case storage = "Storage"
    case logs = "Logs"

    var id: String { rawValue }
}

/// Shared two-column settings screen (nav list + detail pane), used by every theme --
/// wired to the .settings icon on SideRail/DockBar that previously did nothing. Content
/// is real AetherEMU concerns (CPU backend status, graphics/controls, import location),
/// not a reproduction of an actual Switch's System Settings category list.
struct SettingsView: View {
    var onDismiss: () -> Void

    // Optional, not SettingsSection: the non-optional-selection List(_:selection:rowContent:)
    // overload is unavailable on iOS (a real CI compile error caught this --
    // "'init(_:selection:rowContent:)' is unavailable in iOS"); the Optional-Binding
    // overload is the one that's actually available cross-platform.
    @State private var section: SettingsSection? = .about

    @State private var isPickingKeys = false
    @State private var isPickingFirmware = false
    @State private var isInstallingFirmware = false
    @State private var systemFilesMessage: String?
    @State private var systemFilesMessageIsError = false

    private var keysInstalled: Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileManager.default.fileExists(atPath: support.appendingPathComponent("keys/prod.keys").path)
    }

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
                        switch section ?? .about {
                        case .about:
                            aboutSection
                        case .systemFiles:
                            systemFilesSection
                        case .graphics:
                            graphicsSection
                        case .controls:
                            controlsSection
                        case .storage:
                            storageSection
                        case .logs:
                            logsSection
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.2), value: section)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
        .fileImporter(isPresented: $isPickingKeys, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                installKeys(from: url)
            case .failure(let error):
                systemFilesMessage = error.localizedDescription
                systemFilesMessageIsError = true
            }
        }
        .fileImporter(isPresented: $isPickingFirmware, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                installFirmware(from: url)
            case .failure(let error):
                systemFilesMessage = error.localizedDescription
                systemFilesMessageIsError = true
            }
        }
    }

    private func installKeys(from url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        guard url.lastPathComponent == "prod.keys" else {
            systemFilesMessage = "Please pick a file named exactly \"prod.keys\"."
            systemFilesMessageIsError = true
            return
        }

        let ok = AetherBridge.shared().installKeys(atPath: url.path)
        systemFilesMessageIsError = !ok
        systemFilesMessage = ok
            ? "Keys installed."
            : "Failed to install keys -- check that title.keys/key_retail.bin (if you have them) sit next to prod.keys."
    }

    private func installFirmware(from url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        isInstallingFirmware = true
        systemFilesMessage = nil

        // installFirmware(atPath:) is synchronous and can take a few seconds for a full
        // firmware set (dozens of NCA files) -- run it off the main thread so the UI
        // (the spinner below) actually stays responsive while it works.
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = AetherBridge.shared().installFirmware(atPath: url.path)
            if needsAccess {
                url.stopAccessingSecurityScopedResource()
            }
            DispatchQueue.main.async {
                isInstallingFirmware = false
                systemFilesMessageIsError = !ok
                systemFilesMessage = ok
                    ? "Firmware installed."
                    : "Failed to install firmware -- make sure the folder contains .nca files directly (not in a subfolder)."
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

    private var systemFilesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent("Keys") {
                Label(keysInstalled ? "Installed" : "Not installed",
                      systemImage: keysInstalled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(keysInstalled ? .green : .secondary)
            }
            LabeledContent("Firmware") {
                Label(AetherBridge.shared().hasFirmwareInstalled ? "Installed" : "Not installed",
                      systemImage: AetherBridge.shared().hasFirmwareInstalled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(AetherBridge.shared().hasFirmwareInstalled ? .green : .secondary)
            }

            Divider()

            Button {
                systemFilesMessage = nil
                isPickingKeys = true
            } label: {
                Label("Import Keys (prod.keys)", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)

            Text("Pick your own prod.keys file. If title.keys or key_retail.bin sit in the same folder, they're picked up automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                systemFilesMessage = nil
                isPickingFirmware = true
            } label: {
                if isInstallingFirmware {
                    Label("Installing…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("Import Firmware Folder", systemImage: "shippingbox.fill")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isInstallingFirmware)

            Text("Pick a folder containing firmware .nca files (extract Nintendo's own firmware archive first -- picking a .zip directly isn't supported yet).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let systemFilesMessage {
                Text(systemFilesMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(systemFilesMessageIsError ? .red : .green)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: systemFilesMessage)
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
            Text("Touch and MFi/PS/Xbox controller input are wired, but untested on real hardware.")
                .foregroundStyle(.secondary)
            Text("No per-game button remapping UI exists yet -- controllers use InputCommon::GameController's default mapping.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Imported games are copied into AetherEMU's own Application Support/Games folder and stay there across relaunches -- you won't be asked to re-pick a file just to open it again.")
                .foregroundStyle(.secondary)
            Text("This does mean each imported game takes roughly double its own size in storage until removed from the Library (the original file, wherever you picked it from, is untouched).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var logsSection: some View {
        LogsSectionView()
    }
}

/// Broken out of SettingsView's body since it owns its own async file-read state --
/// reads the tail of the engine's real log file (EdenPath::LogDir/eden_log.txt, written
/// by Common::Log once EmulationSession::InitializeApplication starts it) and offers it
/// for sharing. Previously nothing on iOS ever started the logging system at all, so
/// this file didn't exist to view until that was fixed.
private struct LogsSectionView: View {
    @State private var tail: String = ""
    @State private var logFileURL: URL?

    private var logDirectory: URL {
        URL(fileURLWithPath: AetherBridge.shared().logDirectory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Log directory", value: logDirectory.path)
                .font(.footnote)
                .textSelection(.enabled)

            if let logFileURL {
                ShareLink(item: logFileURL) {
                    Label("Share Log File", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Last 4 KB of the current log:")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(tail.isEmpty ? "(no log output yet)" : tail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 320)
            .padding(10)
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let candidate = logDirectory.appendingPathComponent("eden_log.txt")
        guard FileManager.default.fileExists(atPath: candidate.path),
              let handle = try? FileHandle(forReadingFrom: candidate) else {
            return
        }
        defer { try? handle.close() }

        logFileURL = candidate

        let size = (try? handle.seekToEnd()) ?? 0
        let tailSize: UInt64 = 4096
        let offset = size > tailSize ? size - tailSize : 0
        try? handle.seek(toOffset: offset)
        if let data = try? handle.readToEnd() {
            tail = String(data: data, encoding: .utf8) ?? "(log contains non-UTF8 data)"
        }
    }
}
