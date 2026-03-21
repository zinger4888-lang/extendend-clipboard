# Extended Clipboard

Extended Clipboard is a native macOS menubar app that keeps a short history of copied text and shows a system-style popup next to the active input when you press `Cmd+V`.

## Features

- menubar app with clipboard history for text items;
- native popup menu anchored near the current input field;
- instant re-copy and paste back into the previously focused app;
- configurable ordering for both the menubar list and the `Cmd+V` popup;
- compact history display with `See More` overflow for items `11-20`;
- launch-at-login support through a `LaunchAgent`.

## Requirements

- macOS 13 or later;
- Swift 6.2 or later;
- Accessibility permission for global `Cmd+V` interception and caret positioning.

## Project Layout

```text
extended-clipboard/
├── App/Info.plist
├── Sources/ExtendedClipboard/ExtendedClipboardApp.swift
├── scripts/build-app.sh
├── scripts/install-app.sh
├── scripts/install-launch-agent.sh
├── scripts/uninstall-launch-agent.sh
└── .github/workflows/ci.yml
```

## Build

Build the app bundle locally:

```bash
cd /Users/zinger/Desktop/codex/extended-clipboard
./scripts/build-app.sh
```

The generated bundle will be placed at:

```text
/Users/zinger/Desktop/codex/extended-clipboard/dist/Extended Clipboard.app
```

## Install

Install the current build into `/Applications`:

```bash
cd /Users/zinger/Desktop/codex/extended-clipboard
./scripts/install-app.sh
open /Applications/Extended\ Clipboard.app
```

## Launch At Login

Enable autostart:

```bash
cd /Users/zinger/Desktop/codex/extended-clipboard
./scripts/install-launch-agent.sh
```

Disable autostart:

```bash
cd /Users/zinger/Desktop/codex/extended-clipboard
./scripts/uninstall-launch-agent.sh
```

## Accessibility

The app needs permission in:

```text
System Settings > Privacy & Security > Accessibility
```

If macOS keeps associating permission with an older build, reset the entry and grant access again for `/Applications/Extended Clipboard.app`:

```bash
tccutil reset Accessibility com.zinger.extended-clipboard
```

## Development

Run a local debug build from the package:

```bash
cd /Users/zinger/Desktop/codex/extended-clipboard
swift build
```

CI uses the same `swift build` path on macOS.

## Releasing

`build-app.sh` supports two signing modes:

- default: ad-hoc signing for local development and testing;
- release: pass `CODESIGN_IDENTITY` to produce a properly signed app bundle.

Example:

```bash
cd /Users/zinger/Desktop/codex/extended-clipboard
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

For a public binary release, use a real Developer ID certificate. The default ad-hoc signature is fine for local use, but it is not the right long-term distribution path for a GitHub release asset.

## Known Limitations

- The app only stores text history. Images and files are ignored by design.
- Popup positioning depends on Accessibility APIs, so some apps may provide less precise caret geometry than others.
- The login item uses `LaunchAgent` plus `open -gj`, which is practical for personal use but not as robust as a dedicated login helper.

## License

MIT. See [LICENSE](LICENSE).
