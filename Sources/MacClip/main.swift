import AppKit
import Carbon
import ApplicationServices

@main
struct MacClipMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = ClipboardAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class ClipboardAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let history = ClipboardHistory()
    private var statusItem: NSStatusItem!
    private var timer: DispatchSourceTimer?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var shortcutAvailable = false
    private var pasteTargetApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "▤"
        statusItem.button?.toolTip = "MacClip clipboard history"
        history.load()
        history.beginMonitoring()
        observeActiveApplication()
        registerGlobalShortcut()
        rebuildMenu()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.8, repeating: 0.8)
        timer.setEventHandler { [weak self] in
            guard let self, history.captureNewCopy() else { return }
            rebuildMenu()
        }
        timer.resume()
        self.timer = timer
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let shortcutTitle = shortcutAvailable
            ? "Clipboard History  (⌃⌘V)"
            : "Keyboard shortcut unavailable"
        menu.addItem(NSMenuItem(title: shortcutTitle, action: nil, keyEquivalent: ""))
        menu.items[0].isEnabled = false
        let hint = NSMenuItem(title: "Press Return or click an item to paste", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        if history.entries.isEmpty {
            let empty = NSMenuItem(title: "Copy text or an image to get started", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (index, entry) in history.entries.enumerated() {
                let item = NSMenuItem(title: Self.menuTitle(for: entry), action: #selector(pasteHistoryItem(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !history.entries.isEmpty
        menu.addItem(clear)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MacClip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private static func menuTitle(for entry: ClipboardEntry) -> String {
        let text = entry.preview.isEmpty ? entry.kind : entry.preview
        let oneLine = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let prefix = entry.kind == "Image" ? "🖼  " : (entry.kind == "Formatted text" ? "▤  " : "")
        return prefix + String(oneLine.prefix(72))
    }

    @objc private func pasteHistoryItem(_ sender: NSMenuItem) {
        guard history.restore(at: sender.tag) else { return }
        guard let target = pasteTargetApplication, !target.isTerminated else {
            showPastePermissionMessage(noTarget: true)
            return
        }

        guard AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary) else {
            showPastePermissionMessage(noTarget: false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak target] in
            guard let target, !target.isTerminated else { return }
            target.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Self.sendCommandV()
            }
        }
    }

    private func showPastePermissionMessage(noTarget: Bool) {
        let alert = NSAlert()
        alert.messageText = noTarget ? "Copied to the clipboard" : "MacClip needs Accessibility permission to paste"
        alert.informativeText = noTarget
            ? "The selected item is on your clipboard. Return to an app and press Command-V to paste it."
            : "The selected item is on your clipboard. To let MacClip press Command-V in the app you were using, enable MacClip under System Settings → Privacy & Security → Accessibility."
        alert.addButton(withTitle: noTarget ? "OK" : "Open Accessibility Settings")
        if !noTarget { alert.addButton(withTitle: "Later") }
        if alert.runModal() == .alertFirstButtonReturn && !noTarget,
           let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    private static func sendCommandV() {
        guard AXIsProcessTrusted(),
              let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func observeActiveApplication() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            pasteTargetApplication = frontmost
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.pasteTargetApplication = app
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            pasteTargetApplication = frontmost
        }
    }

    private func registerGlobalShortcut() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var pressedHotKey = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKey
                )
                guard status == noErr, pressedHotKey.id == 1 else { return noErr }
                let delegate = Unmanaged<ClipboardAppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.openHistoryFromShortcut() }
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            NSLog("MacClip could not install its keyboard shortcut handler (\(handlerStatus))")
            return
        }

        let identifier = EventHotKeyID(signature: 0x4D434C50, id: 1) // "MCLP"
        let shortcutStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(controlKey | cmdKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if shortcutStatus != noErr {
            NSLog("MacClip could not register Control-Command-V (\(shortcutStatus))")
        } else {
            shortcutAvailable = true
        }
    }

    private func openHistoryFromShortcut() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            pasteTargetApplication = frontmost
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let menu = statusItem.menu else { return }
        menu.update()

        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        guard let screen else { return }

        let bounds = screen.frame
        let size = menu.size
        var location = NSPoint(x: pointer.x + 14, y: pointer.y - 14)
        if location.x + size.width > bounds.maxX {
            location.x = pointer.x - size.width - 14
        }
        if location.y - size.height < bounds.minY {
            location.y = pointer.y + 14
        }
        location.x = min(max(location.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        location.y = min(max(location.y, bounds.minY + size.height), bounds.maxY)

        menu.popUp(
            positioning: nil,
            at: location,
            in: nil
        )
    }

    @objc private func clearHistory() {
        history.clear()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.cancel()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

struct ClipboardItem: Codable, Equatable {
    var representations: [String: Data]
}

struct ClipboardEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var items: [ClipboardItem]
    var preview: String
    var kind: String

    var byteCount: Int {
        items.reduce(0) { sum, item in
            sum + item.representations.values.reduce(0) { $0 + $1.count }
        }
    }
}

/// A private, local history of recent clipboard items, including text and images.
final class ClipboardHistory {
    private(set) var entries: [ClipboardEntry] = []
    private let pasteboard = NSPasteboard.general
    private var observedChangeCount: Int?
    private let limit = 30
    private let maxEntryBytes = 16 * 1024 * 1024
    private let maxHistoryBytes = 64 * 1024 * 1024

    private var historyURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MacClip", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        if let saved = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
            entries = Array(saved.prefix(limit))
        } else if let legacyText = try? JSONDecoder().decode([String].self, from: data) {
            entries = legacyText.prefix(limit).map { text in
                let item = ClipboardItem(representations: [NSPasteboard.PasteboardType.string.rawValue: Data(text.utf8)])
                return ClipboardEntry(id: UUID(), items: [item], preview: text, kind: "Text")
            }
            save()
        }
    }

    func beginMonitoring() {
        observedChangeCount = pasteboard.changeCount
    }

    @discardableResult
    func captureNewCopy() -> Bool {
        let currentCount = pasteboard.changeCount
        guard let observedChangeCount else {
            self.observedChangeCount = currentCount
            return false
        }
        guard currentCount != observedChangeCount else { return false }
        self.observedChangeCount = currentCount

        guard let sourceItems = pasteboard.pasteboardItems, !sourceItems.isEmpty else { return false }

        var remaining = maxEntryBytes
        var capturedItems: [ClipboardItem] = []
        for sourceItem in sourceItems {
            let orderedTypes = sourceItem.types.sorted { Self.typePriority($0) < Self.typePriority($1) }
            var representations: [String: Data] = [:]
            for type in orderedTypes {
                guard let data = sourceItem.data(forType: type), !data.isEmpty,
                      data.count <= remaining else { continue }
                representations[type.rawValue] = data
                remaining -= data.count
            }
            if !representations.isEmpty {
                capturedItems.append(ClipboardItem(representations: representations))
            }
        }
        guard !capturedItems.isEmpty else { return false }

        let text = pasteboard.string(forType: .string) ?? ""
        let typeNames = capturedItems.flatMap { $0.representations.keys }
        let isImage = typeNames.contains { name in
            ["public.png", "public.tiff", "public.jpeg", "public.heic", "public.image"].contains(name)
        }
        let isFormatted = typeNames.contains { name in
            ["public.rtf", "com.apple.rtfd", "public.html"].contains(name)
        }
        let kind = isImage ? "Image" : (isFormatted ? "Formatted text" : "Text")
        let preview = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind : text
        let newEntry = ClipboardEntry(id: UUID(), items: capturedItems, preview: preview, kind: kind)
        guard newEntry.byteCount <= maxEntryBytes else { return false }
        entries.removeAll { $0.items == newEntry.items }
        entries.insert(newEntry, at: 0)
        trimHistory()
        save()
        return true
    }

    @discardableResult
    func restore(at index: Int) -> Bool {
        guard entries.indices.contains(index) else { return false }
        let entry = entries[index]
        let restoredItems = entry.items.map { storedItem -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (rawType, data) in storedItem.representations {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: rawType))
            }
            return item
        }
        guard !restoredItems.isEmpty else { return false }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(restoredItems) else { return false }
        observedChangeCount = pasteboard.changeCount
        entries.remove(at: index)
        entries.insert(entry, at: 0)
        save()
        return true
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: historyURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            NSLog("MacClip could not save clipboard history: %@", error.localizedDescription)
        }
    }

    private func trimHistory() {
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        var total = entries.reduce(0) { $0 + $1.byteCount }
        while total > maxHistoryBytes, !entries.isEmpty {
            total -= entries.removeLast().byteCount
        }
    }

    private static func typePriority(_ type: NSPasteboard.PasteboardType) -> Int {
        switch type.rawValue {
        case "public.png", "public.tiff", "public.jpeg", "public.heic": 0
        case "public.rtf", "com.apple.rtfd", "public.html": 1
        case NSPasteboard.PasteboardType.string.rawValue: 2
        default: 3
        }
    }
}
