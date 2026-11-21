# Mac Utilities

Two small, native macOS menu-bar apps built with Swift:

- **MacSpeed** shows live network download speed and upload speed in its menu.
- **MacClip** keeps a local clipboard history and can paste a selected item into the app you were using.

## Requirements

- macOS 13 or later
- Swift 5.9 or later (included with Xcode Command Line Tools)

## Build and open

Open Terminal, change to this folder, then build either app:

```sh
./build-app.sh
open MacSpeed.app
```

```sh
./build-clip-app.sh
open MacClip.app
```

Each script creates its `.app` bundle in this folder. Both apps live in the menu bar and do not show a Dock icon. To start one automatically after sign-in, add its app bundle in **System Settings → General → Login Items → Open at Login**.

## MacSpeed

MacSpeed refreshes once per second. Its menu-bar item shows download speed; click it to see upload speed too. Units adjust automatically from B/s through KB/s, MB/s, and GB/s. Rates use decimal byte units (1 KB = 1,000 bytes). MacSpeed reads network-interface counters provided by macOS and does not need network access permission.

## MacClip

Press **Control–Command–V** from any app to open clipboard history beside the pointer, or click the MacClip menu-bar icon. Use the arrow keys and **Return**, or click an entry, to paste it into the app that was active before MacClip opened.

MacClip stores up to 30 recent entries locally, including the image and rich-text formats provided by the source app. History is limited to 64 MB total and 16 MB per entry. The menu shows a text preview when available and labels image entries.

Automatic paste requires permission to send the Command–V keystroke. Enable MacClip under **System Settings → Privacy & Security → Accessibility** when prompted. Without that permission, selecting an item still restores it to the clipboard; paste it manually with **Command–V**.

Copied content is saved on this Mac at:

```text
~/Library/Application Support/MacClip/history.json
```

Choose **Clear History** in the MacClip menu to erase it. To copy a screenshot into the clipboard for MacClip, hold Control while using the screenshot shortcut—for example, **Control–Shift–Command–4** for a selected area. The usual **Shift–Command–4** saves the screenshot as a file instead.

## Source layout

- `Sources/MacSpeed/main.swift` — MacSpeed app
- `Sources/MacClip/main.swift` — MacClip app
- `Info.plist` and `Info-clip.plist` — app bundle settings
- `build-app.sh` and `build-clip-app.sh` — build the app bundles

The generated `.app` bundles and Swift build cache are excluded from Git; build them locally using the commands above.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
