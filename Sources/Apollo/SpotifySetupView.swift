import SwiftUI

struct SpotifySetupView: View {
    @ObservedObject var connection: SpotifyConnection
    var changed: () -> Void
    @State private var expanded = false
    var body: some View {
        DisclosureGroup("Spotify playlist connection", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to follow playlists you own or collaborate on. Other playlists use the playing album. Desktop playback works without this connection.")
                    .font(.caption).foregroundStyle(.secondary)
                if !connection.connected {
                    Link("1. Open Spotify developer dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                    Text("Create an app, enable Web API, and add this exact redirect URI. Add your account to the app’s allowed users if Spotify requires it.").font(.caption)
                    Text(SpotifyConnection.redirect).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    TextField("2. Paste Client ID (no secret needed)", text: $connection.clientID).textFieldStyle(.roundedBorder).disabled(connection.busy)
                    Text("Spotify applies account eligibility and user limits to development apps. Wider access requires Spotify approval.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if connection.connected || connection.busy {
                        Button(connection.busy ? "Cancel sign-in" : "Disconnect Spotify", action: connection.disconnect)
                    } else {
                        Button("3. Connect Spotify", action: connection.connect)
                    }
                    if connection.busy { ProgressView().controlSize(.small) }
                }
                Text(connection.message).font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
        .onChange(of: connection.connected) { _, _ in changed() }
    }
}
