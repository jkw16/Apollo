import SwiftUI
import AppKit

struct LyricOptionsView: View {
    @ObservedObject var model: ApolloModel
    @State private var screens = NSScreen.screens
    private var appearance: Binding<LyricAppearance> { $model.lyricAppearance }
    private var availableHeight: CGFloat { min(790, max(400, (NSScreen.main?.visibleFrame.height ?? 850) - 75)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                section("Style")
                ForEach(LyricStyle.allCases) { style in
                    choice(style.rawValue, selected: model.lyricAppearance.style == style) { model.lyricAppearance.style = style }
                }
                separator
                choice("Keep Screen Awake", selected: model.lyricAppearance.keepScreenAwake) { model.lyricAppearance.keepScreenAwake.toggle() }
                    .help("Prevent display idle sleep while lyrics are visible and music is playing. Pause or turn this off to allow sleep.")
                choice("Non-lockscreen Visibility", selected: model.lyricAppearance.desktopVisible) { model.lyricAppearance.desktopVisible.toggle() }
                    .help("Show floating lyrics on the selected display while Apollo is in the background. Never overlays the lock screen.")
                separator
                section("Lyric Timing")
                HStack {
                    Button("Earlier") { model.updateOffset(model.lyricOffset + 0.1) }
                    Text(String(format: "%+.1f s", model.lyricOffset)).monospacedDigit()
                    Button("Later") { model.updateOffset(model.lyricOffset - 0.1) }
                    Button("Reset") { model.updateOffset(0) }
                }.controlSize(.small).padding(.horizontal, 8).disabled(model.trackID.isEmpty)
                Text("Lyrics late? Tap Earlier. Saved for this song. Visual uses per-word animation. Word timing is estimated when only line timestamps are available.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
                separator
                section("Font")
                ForEach(LyricTypeface.allCases) { face in
                    choice(face.rawValue, selected: model.lyricAppearance.typeface == face, font: face.font(size: 16)) { model.lyricAppearance.typeface = face }
                }
                separator
                HStack { section("Text Size"); Spacer(); Text("\(Int(model.lyricAppearance.textSize)) pt").font(.caption).foregroundStyle(.secondary).padding(.trailing, 8) }
                HStack(spacing: 12) {
                    Slider(value: appearance.textSize, in: 20...60, step: 1).accessibilityLabel("Lyric text size")
                    Button("Reset") { model.lyricAppearance.textSize = 33 }.buttonStyle(.bordered).controlSize(.small)
                }.padding(.horizontal, 8).padding(.vertical, 5)
                separator
                section("Display")
                Menu {
                    Button { model.lyricAppearance.displayID = "automatic" } label: {
                        Label("Follow Apollo", systemImage: model.lyricAppearance.displayID == "automatic" ? "checkmark" : "display")
                    }
                    ForEach(screens, id: \.apolloDisplayID) { screen in
                        Button { model.lyricAppearance.displayID = screen.apolloDisplayID } label: {
                            Label(screen.localizedName, systemImage: model.lyricAppearance.displayID == screen.apolloDisplayID ? "checkmark" : "display")
                        }
                    }
                } label: {
                    HStack { Text(displayName); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary) }
                        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 6)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Lyrics display: \(displayName)")
                separator
                section("Color")
                choice("Auto Sync", selected: model.lyricAppearance.autoSync) { model.lyricAppearance.autoSync.toggle() }
                    .help("Use a color sampled from the current album artwork. Uses Apollo orange when artwork is unavailable.")
                colorRow("Lyric Text…", keyPath: \.lyricText)
                colorRow("Highlight…", keyPath: \.highlight)
                colorRow("Secondary Text…", keyPath: \.secondaryText)
                choice("Reset Colors", selected: false) { model.lyricAppearance.resetColors() }
                separator
                choice("Automatic Lyrics", selected: model.automaticLyricsEnabled) { model.automaticLyricsEnabled.toggle() }
                Text(model.lyricStatus).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 26)
                Link("Lyrics by LRCLIB", destination: URL(string: "https://lrclib.net")!).font(.caption).padding(.horizontal, 26)
                choice("Import Timed Lyrics…", selected: false) {
                    model.showLyricOptions = false
                    DispatchQueue.main.async { model.importLyrics() }
                }
            }.padding(10)
        }
        .frame(width: 305, height: availableHeight)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
    }

    private var displayName: String {
        if model.lyricAppearance.displayID == "automatic" { return NSScreen.main?.localizedName ?? "Follow Apollo" }
        return screens.first(where: { $0.apolloDisplayID == model.lyricAppearance.displayID })?.localizedName ?? "Display disconnected · Follow Apollo"
    }
    private var separator: some View { Divider().padding(.vertical, 7).padding(.horizontal, 2) }
    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 26).padding(.vertical, 4)
    }
    private func choice(_ title: String, selected: Bool, font: Font = .system(size: 16), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).opacity(selected ? 1 : 0).frame(width: 22)
                Text(title).font(font)
                Spacer(minLength: 0)
            }.padding(.vertical, 4).padding(.trailing, 5).contentShape(Rectangle())
        }.buttonStyle(LyricMenuButtonStyle()).accessibilityValue(selected ? "Selected" : "Not selected")
    }
    private func colorRow(_ title: String, keyPath: WritableKeyPath<LyricAppearance, LyricColor>) -> some View {
        HStack(spacing: 8) {
            ColorPicker(title, selection: Binding(
                get: { model.lyricAppearance[keyPath: keyPath].color },
                set: { model.lyricAppearance[keyPath: keyPath] = LyricColor($0); model.lyricAppearance.autoSync = false }
            ), supportsOpacity: false).labelsHidden().fixedSize().accessibilityLabel(title)
            Text(title).font(.system(size: 16))
            Spacer()
        }.padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 4)
    }
}

private struct LyricMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }
    private struct HoverRow: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label.foregroundStyle(.primary)
                .background((hovering || configuration.isPressed) ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .onHover { hovering = $0 }
        }
    }
}
