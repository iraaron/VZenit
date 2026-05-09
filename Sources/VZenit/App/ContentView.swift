// ContentView.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS
//
// Root view: three-panel layout — sidebar (library), main editor, inspector.

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var library:       VZLibraryManager
    @EnvironmentObject var midi:          MIDIManager
    @EnvironmentObject var updateChecker: UpdateChecker

    @State private var selectedPatchID: UUID?        = nil
    @State private var editorTab: EditorTab          = .voice
    @State private var showMIDISheet                 = false
    @State private var showImportSheet               = false
    @State private var showExportSheet               = false
    @State private var alertMessage: String?         = nil
    @State private var updateBannerDismissed         = false

    // The patch currently being edited (copy-on-change, sent when auto-update is on)
    @State private var editingPatch: VZVoicePatch?   = nil
    @State private var autoUpdate                    = false

    enum EditorTab: String, CaseIterable {
        case voice     = "Voice Editor"
        case operation = "Operation"
        case global    = "Global"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let update = updateChecker.availableUpdate, !updateBannerDismissed {
                UpdateBannerView(update: update) { updateBannerDismissed = true }
            }
            NavigationSplitView {
                libraryPanel
            } detail: {
                editorPanel
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showMIDISheet) { MIDISettingsSheet() }
        .alert("Error", isPresented: .init(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .importSysEx)) { _ in
            showImportSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .sendCurrentPatch)) { _ in
            sendCurrentPatch()
        }
        .fileImporter(
            isPresented: $showImportSheet,
            allowedContentTypes: [.init(filenameExtension: "syx")!, .json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showExportSheet,
            document: SyxDocument(patch: editingPatch),
            contentType: .init(filenameExtension: "syx")!,
            defaultFilename: editingPatch?.name.trimmingCharacters(in: .whitespaces) ?? "patch"
        ) { result in
            if case .failure(let err) = result { alertMessage = err.localizedDescription }
        }
        .onChange(of: selectedPatchID) { _, id in
            if let id, let p = library.patch(id: id) { editingPatch = p }
        }
        .onChange(of: midi.receivedPatch) { _, patch in
            guard let patch else { return }
            editingPatch = patch
        }
    }

    // MARK: - Library sidebar

    private var libraryPanel: some View {
        VStack(spacing: 0) {
            // Toolbar inside sidebar
            HStack {
                Text(library.metadata.name)
                    .font(.headline)
                Spacer()
                Button { library.add(VZVoicePatch.random()) } label: { Image(systemName: "die.face.5") }
                    .help("Add random patch")
                Button { library.add(VZVoicePatch()) } label: { Image(systemName: "plus") }
                    .help("Add new patch")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            List(library.patches, selection: $selectedPatchID) { patch in
                PatchRow(patch: patch)
                    .tag(patch.id)
                    .contextMenu {
                        Button("Duplicate") { duplicatePatch(patch) }
                        Button("Export SysEx…") { exportSinglePatch(patch) }
                        Divider()
                        Button("Delete", role: .destructive) { library.remove(id: patch.id) }
                    }
            }
            .listStyle(.sidebar)

            Divider()

            // MIDI status bar
            HStack {
                Circle()
                    .fill(midi.isReady ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(midi.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 220, idealWidth: 260)
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 350)
    }

    // MARK: - Editor panel

    private var editorPanel: some View {
        Group {
            if let patch = Binding($editingPatch) {
                VStack(spacing: 0) {
                    // MIDI controls bar
                    MIDIControlBar(
                        patch:        patch,
                        autoUpdate:  $autoUpdate,
                        onSend:       { sendCurrentPatch() },
                        onGet:        { midi.requestVoiceDump() }
                    )

                    Divider()

                    // Tab picker
                    Picker("Tab", selection: $editorTab) {
                        ForEach(EditorTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                    Divider()

                    // Tab content
                    switch editorTab {
                    case .voice:
                        VoiceEditorView(patch: patch)
                    case .operation:
                        OperationPlaceholderView()
                    case .global:
                        GlobalEditorView(patch: patch)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Patch Selected",
                    systemImage: "pianokeys",
                    description: Text("Select a patch from the library, or press Get to receive from the synth.")
                )
            }
        }
        .onChange(of: editingPatch) { _, patch in
            guard autoUpdate, let patch else { return }
            midi.sendVoice(patch)
            // Push changes back to library if a patch is selected there
            if selectedPatchID != nil { library.update(patch) }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { showMIDISheet = true } label: {
                Label("MIDI Settings", systemImage: "cable.connector")
            }
            .help("Configure MIDI ports")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                guard let patch = editingPatch, selectedPatchID != nil else { return }
                library.update(patch)
            } label: {
                Label("Save to Library", systemImage: "square.and.arrow.down")
            }
            .disabled(editingPatch == nil)
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $autoUpdate) {
                Label("Auto Update", systemImage: "arrow.triangle.2.circlepath")
            }
            .toggleStyle(.button)
            .help("Automatically send changes to synth")
        }
    }

    // MARK: - Actions

    private func sendCurrentPatch() {
        guard let patch = editingPatch else { return }
        midi.sendVoice(patch)
    }

    private func duplicatePatch(_ patch: VZVoicePatch) {
        var copy   = patch
        copy.id    = UUID()
        copy.name  = patch.name + " Copy"
        library.add(copy)
        selectedPatchID = copy.id
    }

    private func exportSinglePatch(_ patch: VZVoicePatch) {
        editingPatch    = patch
        showExportSheet = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let imported = try library.importSysEx(from: url)
                if let first = imported.first { selectedPatchID = first.id }
            } catch {
                alertMessage = error.localizedDescription
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
    }
}

// MARK: - Supporting views

struct PatchRow: View {
    let patch: VZVoicePatch
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(patch.name.trimmingCharacters(in: .whitespaces))
                .font(.system(.body, design: .monospaced))
            if !patch.group.isEmpty {
                Text(patch.group)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MIDIControlBar: View {
    @Binding var patch: VZVoicePatch
    @Binding var autoUpdate: Bool
    var onSend: () -> Void
    var onGet:  () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Patch Name", text: $patch.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 200)

            Spacer()

            Button("Get", action: onGet)
                .help("Request current patch from synth")
            Button("Send", action: onSend)
                .buttonStyle(.borderedProminent)
                .help("Send patch to synth")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct OperationPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Operation Editor",
            systemImage: "music.quarternote.3",
            description: Text("Operation (multi-timbral) editing coming in a future release.")
        )
    }
}

// MARK: - Simple FileDocument wrapper for SysEx export

import UniformTypeIdentifiers

struct SyxDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.init(filenameExtension: "syx")!] }

    var patch: VZVoicePatch?

    init(patch: VZVoicePatch? = nil) { self.patch = patch }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        let bytes = [UInt8](data)
        patch = try? VZSysEx.decode(bytes)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let bytes = patch.map { VZSysEx.encode($0) } ?? []
        return FileWrapper(regularFileWithContents: Data(bytes))
    }
}
