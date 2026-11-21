import AppKit
import Darwin

@main
struct MacSpeedMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: DispatchSourceTimer?
    private let meter = NetworkMeter()
    private var downloadLabel: NSMenuItem!
    private var uploadLabel: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "↓ 0 B/s"
        statusItem.button?.toolTip = "Current network download speed"

        let menu = NSMenu()
        downloadLabel = NSMenuItem(title: "↓ Download: 0 B/s", action: nil, keyEquivalent: "")
        uploadLabel = NSMenuItem(title: "↑ Upload: 0 B/s", action: nil, keyEquivalent: "")
        downloadLabel.isEnabled = false
        uploadLabel.isEnabled = false
        menu.addItem(downloadLabel)
        menu.addItem(uploadLabel)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacSpeed", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        statusItem.menu = menu

        meter.start()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.refreshSpeeds() }
        timer.resume()
        self.timer = timer
    }

    private func refreshSpeeds() {
        let (download, upload) = meter.sample()
        let down = Self.format(download)
        let up = Self.format(upload)
        statusItem.button?.title = "↓ \(down)"
        downloadLabel.title = "↓ Download: \(down)"
        uploadLabel.title = "↑ Upload: \(up)"
    }

    private static func format(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(0, bytesPerSecond)
        var unit = 0
        while value >= 1_000 && unit < units.count - 1 {
            value /= 1_000
            unit += 1
        }
        let number = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(number) \(units[unit])"
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.cancel()
    }
}

/// Samples byte counters for active, non-loopback interfaces and computes rates
/// from successive snapshots. Rates use decimal units (1 KB = 1,000 bytes).
final class NetworkMeter {
    private var previous: (incoming: UInt64, outgoing: UInt64, time: TimeInterval)?

    func start() {
        previous = snapshot()
    }

    func sample() -> (download: Double, upload: Double) {
        guard let current = snapshot() else { return (0, 0) }
        defer { previous = current }
        guard let previous, current.time > previous.time else { return (0, 0) }

        let elapsed = current.time - previous.time
        let received = current.incoming >= previous.incoming ? current.incoming - previous.incoming : 0
        let sent = current.outgoing >= previous.outgoing ? current.outgoing - previous.outgoing : 0
        return (Double(received) / elapsed, Double(sent) / elapsed)
    }

    private func snapshot() -> (incoming: UInt64, outgoing: UInt64, time: TimeInterval)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var incoming: UInt64 = 0
        var outgoing: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let address = cursor {
            let item = address.pointee
            cursor = item.ifa_next
            guard let name = item.ifa_name,
                  String(cString: name) != "lo0",
                  let interfaceAddress = item.ifa_addr,
                  interfaceAddress.pointee.sa_family == UInt8(AF_LINK),
                  item.ifa_flags & UInt32(IFF_UP) != 0,
                  item.ifa_flags & UInt32(IFF_RUNNING) != 0,
                  let rawData = item.ifa_data else { continue }

            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            incoming &+= UInt64(data.ifi_ibytes)
            outgoing &+= UInt64(data.ifi_obytes)
        }

        return (incoming, outgoing, ProcessInfo.processInfo.systemUptime)
    }
}
