import SwiftUI
import ApolloCore
import AppKit

struct ContentView: View {
    @ObservedObject var model: ApolloModel
    @State private var immersive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            if !immersive { sidebar.frame(width: 215) }
            VStack(spacing: 0) {
                header.padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 20)
                stage.padding(.horizontal, immersive ? 12 : 28)
                transport.padding(.horizontal, 32).padding(.vertical, 22)
            }
        }
        .frame(minWidth: 980, minHeight: 700)
        .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        .tint(apolloOrange)
        .sheet(isPresented: $model.showSettings) { settings }
        .sheet(isPresented: $model.showMusicSetup) { MusicConnectionView(model: model) }
        .alert("Apollo", isPresented: Binding(get: { model.error != nil && !model.showSettings && !model.showMusicSetup }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "sun.max.fill").font(.system(size: 26)).foregroundStyle(apolloOrange)
                Text("apollo").font(.system(size: 29, weight: .semibold, design: .rounded)).tracking(-1.5)
            }.padding(.top, 38).padding(.bottom, 6)
            Text("MAKE ROOM FOR MUSIC").font(.system(size: 8, weight: .bold)).tracking(2.1).foregroundStyle(.secondary)
                .padding(.bottom, 44)
            eyebrow("YOUR SOURCES").padding(.bottom, 14)
            ForEach(MusicSource.allCases) { source in
                Button { model.select(source) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: source.symbol).frame(width: 18)
                        Text(source.rawValue).font(.system(size: 13, weight: .medium))
                        Spacer()
                        if model.source == source { Circle().fill(apolloOrange).frame(width: 5, height: 5) }
                    }.padding(.horizontal, 12).padding(.vertical, 13)
                        .foregroundStyle(model.source == source ? .white : .white.opacity(0.5))
                        .background(model.source == source ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.bottom, 4)
            }
            Divider().overlay(.white.opacity(0.05)).padding(.vertical, 26)
            eyebrow("SET THE SCENE").padding(.bottom, 16)
            sideAction("Timed lyrics", icon: "text.alignleft") { model.showLyricOptions.toggle() }
                .popover(isPresented: $model.showLyricOptions, arrowEdge: .trailing) { LyricOptionsView(model: model) }
            sideAction("Motion artwork", icon: "rectangle.on.rectangle", active: model.ambientScene == .wallOfSound, action: model.toggleWall)
            sideAction("YouTube video", icon: "play.rectangle") { model.showSettings = true }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: "waveform.path").foregroundStyle(apolloOrange); Text("Your music. Your space.").font(.system(size: 11, weight: .medium)) }
                Text("Built for the moments\nbetween everything else.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            HStack { Text("APOLLO  /  \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")").font(.system(size: 9, weight: .medium)).tracking(1); Spacer(); Image(systemName: "arrow.up.right") }
                .foregroundStyle(.tertiary).padding(.top, 23).padding(.bottom, 24)
        }.padding(.horizontal, 20).background(Color.black.opacity(0.22))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                eyebrow("THE LISTENING ROOM")
                Text("Stay for a song.").font(.system(size: 24, weight: .medium, design: .rounded))
            }
            Spacer()
            HStack(spacing: 6) { Circle().fill(model.connected ? .green : apolloOrange).frame(width: 5, height: 5); Text(model.status).font(.system(size: 10)) }
                .foregroundStyle(.secondary).padding(10).background(.white.opacity(0.045), in: Capsule())
            if model.source != .demo && !model.connected {
                Button(model.isConnecting ? "Connecting…" : "Connect") {
                    if model.source == .apple { model.showMusicSetup = true } else { model.connect() }
                }.buttonStyle(.borderedProminent).controlSize(.small).disabled(model.isConnecting)
            }
            iconButton("Settings", "slider.horizontal.3") { model.showSettings = true }
        }
    }

    private var stage: some View {
        GeometryReader { geometry in
            let wallActive = model.ambientScene == .wallOfSound && model.moviePlayer == nil && model.videoID == nil
            ZStack {
                if wallActive {
                    WallOfSound(covers: model.wallCovers, directory: model.coverDirectory, playing: model.clock.playing)
                } else {
                    Aurora(playing: model.clock.playing && NSApp.isActive)
                }
                if model.videoID == nil {
                    if let player = model.moviePlayer {
                        MotionArtwork(player: player).allowsHitTesting(false)
                    } else if let art = model.artwork, !wallActive {
                        Image(nsImage: art).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped().blur(radius: 45).opacity(0.5)
                    }
                    LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: 7) { Image(systemName: model.videoID == nil ? "sparkles" : "play.rectangle"); Text(model.videoID == nil ? "IMMERSIVE SPACE" : "YOUTUBE COMPANION") }
                            .font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        iconButton(immersive ? "Show sidebar" : "Hide sidebar", "sidebar.left") { immersive.toggle() }
                        iconButton("Fullscreen", "arrow.up.left.and.arrow.down.right") { NSApp.keyWindow?.toggleFullScreen(nil) }
                    }.padding(25)
                    if let id = model.videoID {
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 10) {
                                YouTubePlayer(videoID: id).frame(minWidth: 320, minHeight: 230)
                                HStack {
                                    Link("Watch on YouTube ↗", destination: URL(string: "https://www.youtube.com/watch?v=\(id)")!)
                                    Spacer()
                                    Button("Close video") { model.videoID = nil }
                                }.font(.caption)
                                Text("Video plays independently. Lyrics follow your music source.").font(.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity)
                            if model.showLyrics { lyricView(compact: true).frame(width: 210) }
                        }.padding(.horizontal, 28).padding(.bottom, 20)
                    } else {
                        HStack(spacing: 44) {
                            if !immersive {
                                VStack(alignment: .leading, spacing: 18) {
                                    cover.frame(width: min(220, geometry.size.width * 0.28), height: min(220, geometry.size.width * 0.28))
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(model.title).font(.system(size: 22, weight: .semibold, design: .rounded)).lineLimit(3)
                                        Text(model.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                                    }
                                    Text(model.album.uppercased()).font(.system(size: 8, weight: .medium)).tracking(1.7).foregroundStyle(.white.opacity(0.35)).lineLimit(2)
                                }.frame(width: min(230, geometry.size.width * 0.3), alignment: .leading)
                            }
                            if model.showLyrics { lyricView(compact: false) }
                            else { Spacer(); Image(systemName: "waveform").font(.system(size: 85, weight: .ultraLight)).foregroundStyle(.white.opacity(0.25)); Spacer() }
                        }.padding(.horizontal, 38).frame(maxHeight: .infinity)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Text(model.source == .demo ? "A VISUAL DEMO. A TASTE OF WHAT’S NEXT." : "\(model.source.rawValue.uppercased())  /  YOUR PERSONAL LISTENING SPACE")
                            .font(.system(size: 8, weight: .medium)).tracking(1.6).foregroundStyle(.white.opacity(0.35))
                        Spacer()
                        Button { model.showLyrics.toggle() } label: { Image(systemName: "quote.bubble").foregroundStyle(model.showLyrics ? apolloOrange : .white.opacity(0.5)) }.buttonStyle(.plain).help("Toggle lyrics")
                    }.padding(26)
                }
                // The glow stays outside the embedded player's rectangle.
                EdgeGlow(intensity: model.intensity, playing: model.clock.playing && NSApp.isActive)
            }.clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private var cover: some View {
        ZStack {
            if let art = model.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.19, green: 0.10, blue: 0.25), Color(red: 0.66, green: 0.25, blue: 0.16), Color(red: 0.96, green: 0.59, blue: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(.white.opacity(0.15), lineWidth: 1).padding(25)
                Circle().stroke(.white.opacity(0.22), lineWidth: 1).padding(40)
                Circle().fill(.black.opacity(0.85)).padding(57).shadow(color: .orange.opacity(0.5), radius: 20, x: 12, y: 2)
                VStack { Text("APOLLO").font(.system(size: 9, weight: .medium)).tracking(4).padding(.top, 17); Spacer(); Text("VOL. 01  /  AFTER HOURS").font(.system(size: 6, weight: .medium)).tracking(2).padding(.bottom, 16) }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 10)).shadow(color: .black.opacity(0.3), radius: 25, y: 20)
    }

    private func lyricView(compact: Bool) -> some View {
        TimedLyricsView(model: model, compact: compact, immersive: immersive)
    }

    private var transport: some View {
        VStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                HStack(spacing: 12) {
                    Text(time(model.clock.elapsed(at: timeline.date)))
                    Slider(value: Binding(get: { model.clock.elapsed(at: timeline.date) }, set: { model.control(.seek($0)) }), in: 0...max(1, model.clock.duration))
                        .controlSize(.mini).accessibilityLabel("Playback position").disabled(model.source != .demo && !model.connected)
                    Text(time(model.clock.duration))
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack {
                HStack(spacing: 8) { Image(systemName: model.source.symbol).foregroundStyle(apolloOrange); Text(model.source.rawValue).font(.system(size: 11, weight: .medium)) }.frame(width: 150, alignment: .leading)
                Spacer()
                HStack(spacing: 28) {
                    iconButton("Previous track", "backward.end.fill") { model.control(.previous) }
                    Button { model.control(.toggle) } label: {
                        Image(systemName: model.clock.playing ? "pause.fill" : "play.fill").font(.system(size: 15)).foregroundStyle(.black).frame(width: 44, height: 44).background(.white, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(model.clock.playing ? "Pause" : "Play")
                    iconButton("Next track", "forward.end.fill") { model.control(.next) }
                }.disabled(model.source != .demo && !model.connected)
                Spacer()
                Toggle(isOn: $model.ringEnabled) { Label("Edge glow", systemImage: "rectangle.inset.filled") }.toggleStyle(.switch).controlSize(.mini).font(.system(size: 11)).frame(width: 150)
            }
        }
    }

    private var settings: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("Make it your space.").font(.title2.bold()); Spacer(); Button("Done") { model.showSettings = false }.keyboardShortcut(.cancelAction) }
            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(apolloOrange).fixedSize(horizontal: false, vertical: true)
            }
            GroupBox("LIGHT & MOTION") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Screen edge glow", isOn: $model.ringEnabled)
                    EdgeDisplayPicker(model: model)
                    HStack { Text("Intensity"); Slider(value: $model.intensity, in: 0.1...1) }
                    Text("Ambient color animation; not an audio spectrum. Respects Reduce Motion.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Import motion artwork…", action: model.importMovie); if model.moviePlayer != nil { Button("Remove artwork", action: model.removeMovie) } }
                    Divider().overlay(.white.opacity(0.08))
                    Picker("Background", selection: $model.ambientScene) {
                        ForEach(AmbientScene.allCases) { scene in Text(scene.label).tag(scene) }
                    }.pickerStyle(.segmented).fixedSize()
                    if model.ambientScene == .wallOfSound {
                        Text("\(model.wallCovers.count) covers from the active playlist. Checks for updates every 30 seconds while the wall is visible. Artwork fills in small batches.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Import album covers…", action: model.importCovers)
                            Button("Refresh playlist", action: model.syncCovers).disabled(model.syncInFlight)
                        }
                        Toggle("Sync album covers automatically", isOn: $model.autoSyncCovers)
                        Text("Shows up to 120 album covers from the first 1,000 playlist tracks. Animation pauses while hidden or playback is paused, and slows in Low Power Mode.").font(.caption).foregroundStyle(.secondary)
                        SpotifySetupView(connection: model.spotifyConnection) {
                            model.resetCoverSync()
                            Task { await model.spotifyPlaylists.reset() }
                        }
                        if let status = model.coverStatus {
                            Text(status).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(10)
            }
            GroupBox("LYRICS") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Find lyrics automatically", isOn: $model.automaticLyricsEnabled)
                    Text("Song details are sent to LRCLIB to find lyrics. Matches are saved on this Mac. Imported lyrics take priority.").font(.caption).foregroundStyle(.secondary)
                    Text(model.lyricStatus).font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Import .lrc file…", action: model.importLyrics); Spacer(); Text("\(model.lyrics.count) timed lines").foregroundStyle(.secondary) }
                    HStack { Text("Timing adjustment"); Spacer(); Text(String(format: "%+.1f s", model.lyricOffset)).monospacedDigit() }
                    Slider(value: Binding(get: { model.lyricOffset }, set: model.updateOffset), in: -10...10, step: 0.1).disabled(model.trackID.isEmpty)
                    Text("Positive values show lyrics earlier. Imports are saved for each track on this Mac.").font(.caption).foregroundStyle(.secondary)
                }.padding(10)
            }
            GroupBox("YOUTUBE COMPANION") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Paste a YouTube video URL", text: $model.videoInput).textFieldStyle(.roundedBorder)
                    HStack { Button("Load video") { model.loadYouTube(); if model.videoID != nil { model.showSettings = false } }; if model.videoID != nil { Button("Remove video") { model.videoID = nil } } }
                    Text("Click Play in the video player. YouTube plays independently beside lyrics and may contain ads. Loading a video connects to YouTube. Use local motion artwork for a full background.").font(.caption).foregroundStyle(.secondary)
                }.padding(10)
            }
            Text("Apollo doesn’t fetch Apple’s proprietary animated covers or lyrics. Use media you own or have permission to use. Spotify’s developer policy restricts synchronizing its recordings with visual media; distribution of that experience needs rights and platform review.").font(.caption).foregroundStyle(.secondary)
        }.padding(28)
        }.frame(width: 600, height: min(850, (NSScreen.main?.visibleFrame.height ?? 900) - 80)).preferredColorScheme(.dark)
    }

    private func eyebrow(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(.white.opacity(0.35)) }
    private func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: 26, height: 26) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.65)).help(title).accessibilityLabel(title)
    }
    private func sideAction(_ title: String, icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: icon).font(.system(size: 12)).foregroundStyle(active ? .white : .white.opacity(0.5))
                Spacer()
                if active { Circle().fill(apolloOrange).frame(width: 4, height: 4) }
            }.padding(.vertical, 11)
        }.buttonStyle(.plain)
    }
    private func time(_ seconds: Double) -> String { let total = Int(max(0, seconds)); return String(format: "%d:%02d", total / 60, total % 60) }
}
