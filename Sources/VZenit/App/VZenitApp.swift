// VZenitApp.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS

import SwiftUI

@main
struct VZenitApp: App {

    @StateObject private var library       = VZLibraryManager()
    @StateObject private var midi          = MIDIManager.shared
    @StateObject private var updateChecker = UpdateChecker.shared

    var body: some Scene {

        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(midi)
                .environmentObject(updateChecker)
                .frame(minWidth: 1000, minHeight: 700)
                .task { updateChecker.checkIfDue() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Library") { library.newLibrary() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("Import SysEx…") { NotificationCenter.default.post(name: .importSysEx, object: nil) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Export SysEx…") { NotificationCenter.default.post(name: .exportSysEx, object: nil) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // MIDI menu
            CommandMenu("MIDI") {
                Button("Request Voice Dump") { midi.requestVoiceDump() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Send Current Patch") { NotificationCenter.default.post(name: .sendCurrentPatch, object: nil) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Refresh MIDI Ports") { midi.refreshEndpoints() }
            }
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let importSysEx      = Notification.Name("vzenit.importSysEx")
    static let exportSysEx      = Notification.Name("vzenit.exportSysEx")
    static let sendCurrentPatch = Notification.Name("vzenit.sendCurrentPatch")
}
