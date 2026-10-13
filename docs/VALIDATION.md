# Developer preview validation

Validated on October 13, 2026 on an Apple Silicon Mac with Swift 6.3.3, targeting macOS 14+.

- Debug build and all four XCTest cases: passed.
- Optimized release build: passed.
- App bundle ad-hoc signature verification: passed.
- Native app launch and main window: passed.
- Demo pause and click-to-seek backwards: passed; seeking to the 24-second lyric updates the transport to 0:24 and preserves pause.
- Main interface and settings visually/accessibility inspected.
- YouTube companion can be loaded and removed; successful online video playback has not yet been verified.

Not yet verified end-to-end: Automation permission flows; live Apple Music/Spotify metadata, artwork and transport; imported video playback; external display hot-plugging; Intel Mac support; notarization; and third-party content licensing/platform approval. These are release gates for a production version.

The workspace’s file synchronization caused Swift to report files changed during initial builds. Copying the same source to an isolated temporary build directory allowed the debug/tests/release builds to pass.
