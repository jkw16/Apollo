# Contributing to Apollo

Open an issue to discuss larger changes. Keep provider integration code separate from views, preserve offline demo mode, and never commit credentials or copyrighted sample media.

Before a pull request:

```sh
swift test
bash scripts/build-app.sh
```

For playback changes, manually check permission denial, a closed source app, pause/resume, seeking backwards, track changes, and reconnecting. For visuals, check Reduce Motion, fullscreen, connected/disconnected external displays, and quitting with edge glow active. For YouTube, check an embeddable video and an embedding-disabled video, player controls, closing the player, and loading a second URL.

Use public documented interfaces. Do not add private lyric endpoints, DRM extraction, stripped YouTube players, hidden ads, or secrets. Explain platform requirements for any new provider. Keep permissions explicit and user-triggered.
