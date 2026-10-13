import SwiftUI

struct MusicConnectionView: View {
    @ObservedObject var model: ApolloModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "music.note").font(.title).foregroundStyle(apolloOrange)
                Spacer()
                Button("Done") { model.showMusicSetup = false }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(model.connected ? "You’re connected." : "Bring Apple Music into Apollo.")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                Text("Use the Music app on this Mac. No extra account, password, or API key in Apollo.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                step(1, "Connect Apple Music", "Apollo opens Music and asks macOS for permission to read your current song and control playback.")
                step(2, "Allow the macOS prompt", "Choose OK or Allow when macOS asks to let Apollo control Music. Already allowed? This step is automatic.")
                step(3, "Play a song in Music", "Sign in there if needed, pick a song, then return to Apollo. Your song and playback position will appear here.")
            }.padding(18).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            if model.isConnecting {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text(model.status) }
                    .accessibilityElement(children: .combine)
            } else if model.connected {
                Label(model.trackID.isEmpty ? "Connected. Play a song in Music to get started." : "Connected · \(model.title)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(apolloOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if model.connected {
                    Button("Open Music", action: model.openMusic).buttonStyle(.borderedProminent)
                } else {
                    Button(model.error == nil ? "Connect Apple Music" : "Try Again", action: model.connect)
                        .buttonStyle(.borderedProminent).disabled(model.isConnecting)
                }
                Button("Automation Settings…", action: model.openAutomationSettings)
                Spacer()
            }
            Text(model.automationDenied
                 ? "Turn on Music under Apollo in Automation, then click Try Again. If Apollo is missing, try connecting again to request permission."
                 : "Permission denied before? Open Automation Settings and turn on Music under Apollo, then try again.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("For animated lyrics, choose Timed lyrics → Import Timed Lyrics… and select an .lrc file for the current song. Apple Music’s built-in lyrics and animated covers aren’t imported automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(28).frame(width: 530).preferredColorScheme(.dark).tint(apolloOrange)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.caption.bold()).frame(width: 25, height: 25)
                .background(apolloOrange.opacity(0.15), in: Circle()).foregroundStyle(apolloOrange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
