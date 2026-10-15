# Motion artwork styles

In Apollo, open the Motion artwork dropdown and choose Album Wall, Turntable, or Album Cover. The full-window modes also expose the Motion artwork dropdown at the top so you can return to Album Wall. Use the fullscreen button for macOS fullscreen. Existing YouTube playback takes precedence until Close video is selected.

- **Album Wall** retains the existing sidebar and lyrics alongside the current playlist’s album wall.
- **Album Cover** uses a muted, aspect-fill video covering the full window. A bottom gradient protects the title, artist, album and existing transport controls. Album artwork is rendered underneath and remains visible until the video has a displayable frame; missing/unreadable video falls back to that artwork. With no artwork, a neutral disc placeholder appears.
- **Turntable** centers an album sleeve over a grooved record with shadows. The record slides partly out on play; its label rotates at 33⅓ RPM and holds its exact angle when paused. The tonearm rotates around its top pivot. The background uses averages sampled from the upper and lower halves of the current artwork. Reduce Motion disables mechanical animation; inactive scenes pause record rendering, and Low Power Mode reduces its frame rate.

## Full implementations and wiring

- `Sources/ApolloCore/ArtworkStyle.swift`: stable style identifiers and accumulated record rotation. The model stores the selected identifier in UserDefaults under `artworkStyle`; unknown values fall back to Album Wall.
- `Sources/Apollo/ArtworkScenes.swift`: full-window cover, static sleeve, artwork color sampling and an AVPlayerLayer with aspect-fill and a first-frame crossfade. Player/current-item failures reveal static artwork. Observations are discarded when the surface detaches.
- `Sources/Apollo/VinylArtworkView.swift`: sleeve, grooves, spinning label, slide animation and pivoted tonearm. It receives artwork and the existing playback clock's `playing` value.
- `Sources/Apollo/ApolloModel.swift`: persisted style, palette refreshed by the existing artwork setter, asynchronous local-video validation, AVQueuePlayer/AVPlayerLooper ownership and cancellation when the current track changes. Playback updates call `updateMoviePlayback()`; Turntable and YouTube pause the background video. Clear/remove cancels pending loads, disables looping and releases the queue.
- `Sources/Apollo/ContentView.swift`: selects the full-window experience ahead of the Album Wall layout, adds the settings/top Motion artwork dropdown and reuses existing metadata, lyric and transport components. Motion artwork opens its own menu with all three choices. Selecting a mode closes the YouTube companion. A source menu is available in the full-window views.
- `Sources/Apollo/ApolloModel+Sync.swift`: album-wall sync runs only in Album Wall style.
- `Tests/ApolloCoreTests/RecordRotationTests.swift`: checks pause/hold/resume and repeated playback polls.

`motion-artwork.patch` beside this document contains the complete new files and exact integration diffs against commit ec78b4b. The changes are already applied in this checkout; do not apply the patch here again.

The looping component uses Apple's [AVPlayerLooper](https://developer.apple.com/documentation/avfoundation/avplayerlooper) with a retained queue and template item. A visually seamless loop still depends on compatible beginning/end frames in the supplied clip. Videos use Apollo's existing per-track local import pipeline; this does not automatically retrieve proprietary animated covers from music services.

## Validation

Automated: 49 tests pass, including two rotation tests. Release build and app signing verification pass.

Live visual/media checks remain pending because the computer-control connection timed out:

1. Choose each style, relaunch, and confirm the selected style persists.
2. Import a video for the current track. In Album Cover, verify silent playback across three loops, resize/fullscreen, and readable controls over a bright clip.
3. Pause at a loop boundary; confirm video remains paused. Resume and change tracks; verify no previous track's video remains. Check a track with no video and an unreadable asset.
4. In Turntable, pause midway through a revolution, wait, then resume: the angle must continue, with the tonearm returning to/from its resting position.
5. Change albums: confirm sleeve, record label, colors and metadata follow the current track. Check missing artwork, Reduce Motion, Low Power Mode, and YouTube precedence.
