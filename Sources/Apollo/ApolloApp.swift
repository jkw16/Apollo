import SwiftUI
import AppKit

@main struct ApolloApp: App {
    @StateObject private var model = ApolloModel()
    @StateObject private var lyricPresentation = LyricPresentation()
    private let edgeWindows = EdgeWindows()
    var body: some Scene {
        Window("Apollo", id: "apollo") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .onChange(of: model.ringEnabled) { _, value in edgeWindows.update(enabled: value, intensity: model.intensity) }
                .onChange(of: model.intensity) { _, value in edgeWindows.update(enabled: model.ringEnabled, intensity: value) }
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); lyricPresentation.attach(model) }
        }
        .defaultSize(width: 1250, height: 810)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Timed Lyrics…", action: model.importLyrics).keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Import Motion Artwork…", action: model.importMovie).keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Import Album Covers…", action: model.importCovers)
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { model.control(.toggle) }.keyboardShortcut("p", modifiers: .command)
                Button("Next Track") { model.control(.next) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Track") { model.control(.previous) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Toggle("Screen Edge Glow", isOn: $model.ringEnabled)
                Button("Enter / Exit Fullscreen") { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
        MenuBarExtra("Apollo", systemImage: "sun.max") {
            Text(model.title)
            Text(model.artist)
            Divider()
            Button("Show Apollo") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.title == "Apollo" })?.makeKeyAndOrderFront(nil) }
            Button("Play / Pause") { model.control(.toggle) }
            Toggle("Screen Edge Glow", isOn: $model.ringEnabled)
            Divider()
            Button("Quit Apollo") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
