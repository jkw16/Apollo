import AppKit
import SwiftUI

extension NSScreen {
    /// Display UUIDs survive reconnects and are independent of screen ordering.
    var edgeGlowID: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
            return "display-\(apolloDisplayID)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

struct EdgeDisplayPicker: View {
    @ObservedObject var model: ApolloModel
    @State private var screens = NSScreen.screens

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Displays", selection: $model.ringAllDisplays) {
                Text("All displays").tag(true)
                Text("Selected displays").tag(false)
            }.pickerStyle(.segmented)
            if !model.ringAllDisplays {
                ForEach(Array(screens.enumerated()), id: \.element.edgeGlowID) { index, screen in
                    Toggle(isOn: Binding(
                        get: { model.ringDisplayIDs.contains(screen.edgeGlowID) },
                        set: { selected in
                            if selected { model.ringDisplayIDs.insert(screen.edgeGlowID) }
                            else { model.ringDisplayIDs.remove(screen.edgeGlowID) }
                        }
                    )) {
                        Label("\(index + 1). \(screen.localizedName)", systemImage: "display")
                    }
                }
                if !screens.contains(where: { model.ringDisplayIDs.contains($0.edgeGlowID) }) {
                    Text("Select a connected display to show the glow.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Selections are remembered when displays reconnect. New displays stay off unless selected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }
}
