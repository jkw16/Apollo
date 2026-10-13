# Developer preview validation

Validated on October 13, 2026 on an Apple Silicon Mac with Swift 6.3.3, targeting macOS 14+.

- Debug build and all four XCTest cases: passed.
- Optimized release build: passed.
- App bundle ad-hoc signature verification: passed.
- Native app launch and main window: passed.
- Demo pause and click-to-seek backwards: passed; seeking to the 24-second lyric updates the transport to 0:24 and preserves pause.
- Main interface and settings visually/accessibility inspected.
- YouTube companion renders the official Google Developers sample video player with controls beside the lyrics and can be removed. Audio/video playback after pressing Play has not yet been verified.
- Invalid video input displays an inline settings error; loading valid input clears it.
- Initial GitHub Actions macOS test/package workflow: passed.

Not yet verified end-to-end: Automation permission flows; live Apple Music/Spotify metadata, artwork and transport; imported video playback; external display hot-plugging; Intel Mac support; notarization; and third-party content licensing/platform approval. These are release gates for a production version.

The workspace’s file synchronization caused Swift to report files changed during initial builds. Copying the same source to an isolated temporary build directory allowed the debug/tests/release builds to pass.
