import AppKit
import SwiftUI
import Combine

/// Owns display placement and the lifetime of the display-sleep assertion.
@MainActor final class LyricPresentation: ObservableObject {
    private weak var model: ApolloModel?
    private var subscriptions = Set<AnyCancellable>()
    private var panel: NSPanel?
    private var activity: NSObjectProtocol?
    private var suspended = false
    private var lastDisplayID: String?

    func attach(_ model: ApolloModel) {
        guard self.model == nil else { return }
        self.model = model
        model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.update() }.store(in: &subscriptions)
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didChangeScreenParametersNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.didMoveNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        }
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.suspended = true; self?.update() }.store(in: &subscriptions)
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.suspended = false; self?.update() }.store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.stop() }.store(in: &subscriptions)
        update()
    }

    private func update() {
        guard let model else { return }
        let settings = model.lyricAppearance
        let mainWindow = NSApp.windows.first { $0.identifier?.rawValue == "apollo" || $0.title == "Apollo" }
        let target = NSScreen.screens.first { $0.apolloDisplayID == settings.displayID } ?? mainWindow?.screen ?? NSScreen.main
        if lastDisplayID != settings.displayID {
            lastDisplayID = settings.displayID
            // Also put the listening room on the chosen screen when it is a normal window.
            if settings.displayID != "automatic", let target, let window = mainWindow, !window.styleMask.contains(.fullScreen) {
                var frame = window.frame
                frame.origin = CGPoint(x: target.visibleFrame.midX - frame.width / 2, y: target.visibleFrame.midY - frame.height / 2)
                window.setFrame(frame, display: true)
            }
        }
        let hasLyrics = model.showLyrics && !model.lyrics.isEmpty
        // Normal floating windows stay below macOS's secure lock screen. Never use screen-saver window levels.
        let showOverlay = settings.desktopVisible && hasLyrics && !NSApp.isActive && !suspended && target != nil
        if showOverlay, let target {
            if panel == nil {
                let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.title = "Apollo Floating Lyrics"
                window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
                window.ignoresMouseEvents = true; window.level = .floating
                window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                window.contentView = NSHostingView(rootView:
                    TimedLyricsView(model: model, floating: true)
                        .padding(.horizontal, 28).padding(.vertical, 8)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 20))
                        .preferredColorScheme(.dark))
                panel = window
            }
            let bounds = target.visibleFrame
            let width = min(620, bounds.width * 0.7)
            let height = min(370, bounds.height * 0.45)
            let frame = CGRect(x: bounds.midX - width / 2, y: bounds.minY + 35, width: width, height: height)
            if panel?.frame != frame { panel?.setFrame(frame, display: true) }
            if panel?.isVisible != true { panel?.orderFrontRegardless() }
        } else { panel?.orderOut(nil) }

        let mainVisible = NSApp.isActive && mainWindow?.isVisible == true && mainWindow?.isMiniaturized == false
        let keepAwake = settings.keepScreenAwake && model.clock.playing && hasLyrics && !suspended && (mainVisible || showOverlay)
        if keepAwake && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: "Apollo is displaying timed lyrics during playback")
        } else if !keepAwake { releaseActivity() }
    }
    private func releaseActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
    private func stop() { panel?.orderOut(nil); releaseActivity() }
}
