// Build for the current Mac: swiftc -O static/topp.swift -o topp
import AppKit
import SwiftUI
import Darwin

private let displayLocale = Locale(identifier: "en")

struct Port: Hashable, Comparable {
    let transport: String
    let number: Int
    var label: String { "\(transport) \(number)" }

    static func < (lhs: Port, rhs: Port) -> Bool {
        (lhs.number, lhs.transport) < (rhs.number, rhs.transport)
    }
}

struct Owner: Hashable {
    let port: Port
    let pid: Int
}

struct PortTraffic {
    let port: Port
    var rx = 0.0
    var tx = 0.0
    var total: Double { rx + tx }
}

struct Counter {
    var rx: UInt64 = 0
    var tx: UInt64 = 0
}

struct Flow: Hashable {
    let owner: Owner
    let endpointPair: String
}

struct ProcessMetadata {
    var path: String?
    var parent: pid_t?
    var user: uid_t?
    var started: Date?

    static func read(pid: Int) -> Self {
        var metadata = Self()
        guard let id = pid_t(exactly: pid), id > 0 else { return metadata }
        var path = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(id, &path, UInt32(path.count)) > 0 { metadata.path = String(cString: path) }
        var keys = [CTL_KERN, KERN_PROC, KERN_PROC_PID, id]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        if sysctl(&keys, 4, &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.stride {
            metadata.parent = info.kp_eproc.e_ppid
            metadata.user = info.kp_eproc.e_ucred.cr_uid
            let time = info.kp_proc.p_un.__p_starttime
            if time.tv_sec > 0 {
                metadata.started = Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
            }
        }
        return metadata
    }
}

struct PortRow: Identifiable {
    enum Field { case process, state, rx, tx }

    let id: Owner
    let process: String
    var metadata = ProcessMetadata()
    var states = Set<String>()
    var rx = 0.0
    var tx = 0.0
    var hasRate = false
    var changed: Set<Field> = []
    var activity: Double { rx + tx }
    var rxText: String { hasRate ? rate(rx) : "—" }
    var txText: String { hasRate ? rate(tx) : "—" }

    var state: String {
        return states.map { $0 == "Listen" ? "Listening" : $0 }.sorted().joined(separator: " · ")
    }

    mutating func markChanges(since old: PortRow) {
        changed = []
        if process != old.process { changed.insert(.process) }
        if states != old.states { changed.insert(.state) }
        if rxText != old.rxText { changed.insert(.rx) }
        if txText != old.txText { changed.insert(.tx) }
    }
}

struct Snapshot {
    var rows = [Owner: PortRow]()
    var counters = [Flow: Counter]()
    private var process: (pid: Int, name: String, metadata: ProcessMetadata)?
    private var columns = [String: Int]()
    private var includesTime = false
    private(set) var captureTime: Double?
    var hasHeader: Bool { columns["bytes_in"] != nil && columns["bytes_out"] != nil }

    mutating func read(_ line: String) {
        // The three requested fields and a trailing empty field follow the name.
        // Split from the right so commas in a process name do not shift columns.
        var fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if fields.last == "" { fields.removeLast() }
        if fields.first == "time" {
            includesTime = true
            fields.removeFirst()
        } else if includesTime && !fields.isEmpty {
            let time = fields.removeFirst()
            if captureTime == nil {
                let parts = time.split(separator: ":").compactMap { Double($0) }
                if parts.count == 3 { captureTime = parts[0] * 3600 + parts[1] * 60 + parts[2] }
            }
        }
        if fields.first == "" {
            columns.removeAll()
            for (i, name) in fields.enumerated().dropFirst() { columns[name] = i }
            process = nil
            return
        }
        guard hasHeader, fields.count > columns.count else { return }
        let headCount = fields.count - columns.count
        let label = fields.prefix(headCount).joined(separator: ",")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        func field(_ name: String) -> String {
            guard let i = columns[name] else { return "" }
            return fields[headCount - 1 + i]
        }
        let parts = label.split(separator: " ", maxSplits: 1)
        let protocols = ["tcp4": "TCP", "tcp6": "TCP", "udp4": "UDP", "udp6": "UDP",
                         "quic4": "QUIC", "quic6": "QUIC"]
        guard parts.count == 2, let transport = protocols[String(parts[0])],
              let arrow = parts[1].range(of: "<->") else {
            process = nil
            if let dot = label.lastIndex(of: "."), let pid = Int(label[label.index(after: dot)...]) {
                let metadata = ProcessMetadata.read(pid: pid)
                var name = String(label[..<dot])
                // nettop truncates names to 15 bytes. Expand the executable name
                // when macOS permits the GUI to look up this PID.
                if name.utf8.count >= 15, let path = metadata.path {
                    let executable = URL(fileURLWithPath: path).lastPathComponent
                    if executable.hasPrefix(name) { name = executable }
                }
                process = (pid, name, metadata)
            }
            return
        }
        let local = parts[1][..<arrow.lowerBound]
        // nettop prints IPv4 as address:port and IPv6 as address.port (including *.port).
        guard let process, let separator = local.lastIndex(where: { $0 == ":" || $0 == "." }),
              let port = Int(local[local.index(after: separator)...]), (1...65535).contains(port)
        else { return }
        let owner = Owner(port: Port(transport: transport, number: port), pid: process.pid)
        let state = field("state")
        rows[owner, default: PortRow(id: owner, process: process.name, metadata: process.metadata)].states.insert(state.isEmpty ? "Bound" : state)
        let key = Flow(owner: owner, endpointPair: label)
        let rx = UInt64(field("bytes_in")), tx = UInt64(field("bytes_out"))
        if rx != nil || tx != nil {
            counters[key, default: Counter()].rx += rx ?? 0
            counters[key, default: Counter()].tx += tx ?? 0
        }
    }

    func rates(since previous: Snapshot?, seconds: Double) -> [Owner: PortRow] {
        var result = rows
        if let previous, seconds > 0 {
            for (key, current) in counters {
                let old = previous.counters[key] ?? Counter()
                result[key.owner]?.hasRate = true
                if current.rx >= old.rx { result[key.owner]?.rx += Double(current.rx - old.rx) / seconds }
                if current.tx >= old.tx { result[key.owner]?.tx += Double(current.tx - old.tx) / seconds }
            }
            // An idle TCP listener has no byte counters of its own.
            for (key, row) in rows where row.states == ["Listen"] {
                result[key]?.hasRate = true
            }
        }
        return result
    }
}

func rate(_ value: Double) -> String {
    let units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var amount = value, index = 0
    while amount >= 1000 && index < units.count - 1 { amount /= 1000; index += 1 }
    return String(format: index > 0 && amount < 10 ? "%.1f %@" : "%.0f %@", amount, units[index])
}

private let endOfSample = "--topp-sample--"

// sudo authenticates on the caller's terminal before it backgrounds the sampler.
// Only fixed system commands run as root. A closed output pipe ends the loop,
// including when the unprivileged GUI is killed. One-shot samples flush even on idle Macs.
func startCollector() throws -> FileHandle {
    let script = """
    trap '' HUP
    exec 2>&1
    while /usr/bin/nettop -n -x -L 1 -J time,state,bytes_in,bytes_out; do
        printf '%s\\n' '\(endOfSample)' || exit
        /bin/sleep 1 || exit
    done
    """
    let pipe = Pipe()
    let pid = try spawn(["/usr/bin/sudo", "-b", "--", "/bin/sh", "-c", script],
                        output: pipe.fileHandleForWriting.fileDescriptor)
    try pipe.fileHandleForWriting.close()
    var status: Int32 = 0
    var waited: pid_t
    repeat { waited = waitpid(pid, &status, 0) } while waited == -1 && errno == EINTR
    guard waited == pid, status == 0 else {
        throw LaunchError("sudo could not start the monitor. Run topp from Terminal using an administrator account.")
    }
    return pipe.fileHandleForReading
}

final class Monitor: ObservableObject {
    @Published var rows = [PortRow]()
    @Published var sortOrder = [KeyPathComparator(\PortRow.id.port.number)] {
        didSet {
            if sortOrder != oldValue { rows = sortedForTable(rows) }
        }
    }
    @Published var selection = Set<Owner>()
    @Published var query = ""
    @Published var status = "Reading ports…"
    @Published var hidden: Set<String>
    var onChange: (() -> Void)?
    // Keep hidden ports saved before the command was renamed to topp.
    private let defaults = UserDefaults(suiteName: "org.4rji.puertosmac")!
    init() { hidden = Set(defaults.stringArray(forKey: "hiddenPorts") ?? []) }

    var visible: [PortRow] { rows.filter { !hidden.contains($0.id.port.label) } }

    var busiestPort: PortTraffic? {
        var totals = [Port: PortTraffic]()
        for row in visible where row.hasRate && row.activity > 0 {
            let port = row.id.port
            totals[port, default: PortTraffic(port: port)].rx += row.rx
            totals[port, default: PortTraffic(port: port)].tx += row.tx
        }
        return totals.values.max {
            if $0.total != $1.total { return $0.total < $1.total }
            return $0.port > $1.port
        }
    }

    var busiest: [PortRow] {
        visible.sorted {
            if $0.activity != $1.activity { return $0.activity > $1.activity }
            if $0.id.port != $1.id.port { return $0.id.port < $1.id.port }
            return $0.id.pid < $1.id.pid
        }
    }

    private func sortedForTable(_ values: [PortRow]) -> [PortRow] {
        values.sorted(using: sortOrder + [KeyPathComparator(\.id.port.number),
                                          KeyPathComparator(\.id.port.transport),
                                          KeyPathComparator(\.id.pid)])
    }

    func applySample(_ sample: [Owner: PortRow]) {
        var additions = sample
        let existing = rows.compactMap { old -> PortRow? in
            guard var row = additions.removeValue(forKey: old.id) else { return nil }
            row.markChanges(since: old)
            return row
        }
        rows = existing + sortedForTable(Array(additions.values))
        if !selection.isSubset(of: sample.keys) { selection.formIntersection(sample.keys) }
    }

    func saveHidden(_ values: Set<String>) {
        hidden = values
        defaults.set(values.sorted(), forKey: "hiddenPorts")
        onChange?()
    }

    func start() {
        DispatchQueue.global(qos: .utility).async {
            var sample = Snapshot(), previous: Snapshot?
            var lastTime = 0.0, diagnostic = ""
            while let line = readLine() {
                guard line == endOfSample else {
                    if line.hasPrefix("nettop:") || line.hasPrefix("sudo:") { diagnostic = line }
                    sample.read(line)
                    continue
                }
                guard sample.hasHeader else { diagnostic = "Unrecognized nettop output format."; break }
                let now = ProcessInfo.processInfo.systemUptime
                var interval = now - lastTime
                if let start = previous?.captureTime, let end = sample.captureTime {
                    interval = end - start
                    if interval < -86_300 { interval += 86_400 } // Midnight
                }
                let rows = sample.rates(since: previous, seconds: interval)
                let note = previous == nil ? "Measuring traffic…" : "Updated at " + Self.clock.string(from: Date())
                DispatchQueue.main.async {
                    self.applySample(rows)
                    self.status = note
                    self.onChange?()
                }
                previous = sample
                sample = Snapshot()
                lastTime = now
            }
            let message = diagnostic.isEmpty ? "Monitoring stopped. Run topp again from Terminal." : diagnostic
            DispatchQueue.main.async {
                self.applySample([:])
                self.status = message
                self.onChange?()
            }
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = displayLocale
        f.timeStyle = .medium
        return f
    }()
}

private let changeColor = NSColor.systemOrange.withAlphaComponent(0.38)

final class ProcessArtwork {
    let icon: NSImage
    let bundle: Bundle?
    let executable: String?
    lazy var menuIcon: NSImage = {
        let image = icon.copy() as! NSImage
        image.size = NSSize(width: 16, height: 16)
        return image
    }()

    private static let cache: NSCache<NSString, ProcessArtwork> = {
        let cache = NSCache<NSString, ProcessArtwork>()
        cache.countLimit = 256
        return cache
    }()

    static func forRow(_ row: PortRow) -> ProcessArtwork {
        let key = "\(row.id.pid)|\(row.metadata.started?.timeIntervalSince1970 ?? 0)|\(row.metadata.path ?? "")|\(row.process)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let artwork = ProcessArtwork(row)
        cache.setObject(artwork, forKey: key)
        return artwork
    }

    private init(_ row: PortRow) {
        let app = pid_t(exactly: row.id.pid).flatMap { $0 > 0 ? NSRunningApplication(processIdentifier: $0) : nil }
        executable = row.metadata.path ?? app?.executableURL?.path
        // For a helper nested inside a .app, use the enclosing application's icon.
        let components = executable.map { URL(fileURLWithPath: $0).pathComponents } ?? []
        let enclosingApp = components.firstIndex { $0.lowercased().hasSuffix(".app") }.map {
            URL(fileURLWithPath: NSString.path(withComponents: Array(components[...$0])))
        }
        let bundleURL = enclosingApp ?? app?.bundleURL
        bundle = bundleURL.flatMap { Bundle(url: $0) }
        if let bundleURL {
            icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        } else if let path = executable {
            icon = NSWorkspace.shared.icon(forFile: path)
        } else {
            icon = app?.icon ?? NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!
        }
    }
}

private struct ProcessDetails: View {
    let row: PortRow
    let artwork: ProcessArtwork

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            Text(verbatim: value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(nsImage: artwork.icon).resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.process).font(.headline).textSelection(.enabled)
                    Text("PID \(String(row.id.pid)) · \(row.id.port.label)").foregroundStyle(.secondary)
                }
            }
            Divider()
            if let bundle = artwork.bundle {
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? bundle.bundleURL.deletingPathExtension().lastPathComponent
                field("Application", name)
                if let id = bundle.bundleIdentifier { field("Bundle ID", id) }
            }
            if let uid = row.metadata.user {
                let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) }
                field("User", name.map { "\($0) (UID \(uid))" } ?? "UID \(uid)")
            }
            if let parent = row.metadata.parent {
                field("Parent process", "PID \(parent)")
            }
            if let start = row.metadata.started {
                field("Started", start.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: displayLocale)))
            }
            field("Executable", artwork.executable ?? "Path unavailable")
        }
        .font(.callout).padding(14).frame(width: 380, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProcessInfoButton: NSViewRepresentable {
    let row: PortRow
    func makeCoordinator() -> Coordinator { Coordinator(row: row) }

    func makeNSView(context: Context) -> NSButton {
        let icon = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)!
        let button = NSButton(image: icon, target: context.coordinator, action: #selector(Coordinator.show(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        let coordinator = context.coordinator
        if coordinator.row.id != row.id || coordinator.row.metadata.started != row.metadata.started
            || coordinator.row.process != row.process || coordinator.row.metadata.path != row.metadata.path {
            coordinator.popover?.close()
        }
        coordinator.row = row
        let label = "Process information for \(row.process) (PID \(row.id.pid))"
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    static func dismantleNSView(_ view: NSButton, coordinator: Coordinator) { coordinator.popover?.close() }

    final class Coordinator: NSObject {
        var row: PortRow
        var popover: NSPopover?
        init(row: PortRow) { self.row = row }

        @objc func show(_ sender: NSButton) {
            if let popover, popover.isShown { popover.performClose(sender); return }
            let details = ProcessDetails(row: row, artwork: ProcessArtwork.forRow(row))
            let host = NSHostingController(rootView: details)
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = host
            popover.contentSize = host.view.fittingSize
            self.popover = popover
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }
}

struct PortWindow: View {
    @ObservedObject var monitor: Monitor

    private var matches: [PortRow] {
        let text = monitor.query.trimmingCharacters(in: .whitespaces)
        return monitor.visible.filter {
            text.isEmpty || "\($0.id.port.label) \($0.process) \($0.id.pid) \($0.state)".localizedCaseInsensitiveContains(text)
        }
    }

    private func cell(_ value: String, changed: Bool) -> some View {
        Text(value)
            .padding(.horizontal, 3)
            .background(changed ? Color(nsColor: changeColor) : .clear,
                        in: RoundedRectangle(cornerRadius: 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by port, process, or PID", text: $monitor.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                Spacer()
                Button("Hide Selected Ports") {
                    let selected = matches.filter { monitor.selection.contains($0.id) }.map { $0.id.port.label }
                    monitor.saveHidden(monitor.hidden.union(selected))
                    monitor.selection.removeAll()
                }
                .disabled(!matches.contains { monitor.selection.contains($0.id) })
                .help("Hide the selected ports and protocols for all processes.")
                Menu("Hidden (\(monitor.hidden.count))") {
                    ForEach(monitor.hidden.sorted(), id: \.self) { port in
                        Button("Show \(port)") { monitor.saveHidden(monitor.hidden.subtracting([port])) }
                    }
                    Divider()
                    Button("Show All") { monitor.saveHidden([]) }
                }
                .fixedSize()
                .disabled(monitor.hidden.isEmpty)
            }.padding(12)
            Divider()
            Table(matches, selection: $monitor.selection, sortOrder: $monitor.sortOrder) {
                TableColumn("Port", value: \.id.port.number) { Text(String($0.id.port.number)).monospacedDigit() }.width(65)
                TableColumn("Protocol") { Text($0.id.port.transport) }.width(65)
                TableColumn("Process", value: \.process) { row in
                    HStack(spacing: 4) {
                        Image(nsImage: ProcessArtwork.forRow(row).icon)
                            .resizable().scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true)
                        cell(row.process, changed: row.changed.contains(.process)).lineLimit(1).help(row.process)
                        Spacer(minLength: 0)
                        ProcessInfoButton(row: row).frame(width: 20, height: 20)
                    }
                }.width(min: 145, ideal: 200)
                TableColumn("PID") { Text(String($0.id.pid)).monospacedDigit() }.width(65)
                TableColumn("State", value: \.state) { cell($0.state, changed: $0.changed.contains(.state)) }.width(min: 95, ideal: 140)
                TableColumn("↓ Inbound") { cell($0.rxText, changed: $0.changed.contains(.rx)).monospacedDigit() }.width(89)
                TableColumn("↑ Outbound") { cell($0.txText, changed: $0.changed.contains(.tx)).monospacedDigit() }.width(89)
            }
            Divider()
            HStack {
                let portCount = Set(matches.map { $0.id.port }).count
                let processCount = Set(matches.map { $0.id.pid }).count
                Text("\(portCount) \(portCount == 1 ? "port" : "ports") · \(processCount) \(processCount == 1 ? "process" : "processes")")
                Spacer()
                Text(monitor.status).lineLimit(2)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 7)
        }.frame(minWidth: 800, minHeight: 320)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let menuMode: Bool
    let monitor = Monitor()
    var window: NSWindow?
    var item: NSStatusItem?
    private let summary = NSMenu()
    private var trackingMenu = false
    private var trafficItems = [NSMenuItem]()
    private var menuOwners = [Owner]()

    init(menuMode: Bool) { self.menuMode = menuMode }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu()
        let appMenu = NSMenu()
        add("Quit topp", to: appMenu, action: #selector(quit), key: "q")
        main.addItem(withTitle: "topp", action: nil, keyEquivalent: "").submenu = appMenu
        let edit = NSMenu(title: "Edit")
        for (label, key, action) in [("Cut", "x", "cut:"), ("Copy", "c", "copy:"), ("Paste", "v", "paste:"), ("Select All", "a", "selectAll:")] {
            edit.addItem(withTitle: label, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        main.addItem(withTitle: edit.title, action: nil, keyEquivalent: "").submenu = edit
        let windows = NSMenu(title: "Window")
        windows.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: windows.title, action: nil, keyEquivalent: "").submenu = windows
        NSApp.mainMenu = main

        if menuMode {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item = status
            if let button = status.button {
                button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "topp")
                button.imagePosition = .imageLeading
                button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                button.target = self
                button.action = #selector(clickStatus)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            add("Open Window", to: summary, action: #selector(openWindow))
            summary.addItem(.separator())
            for _ in 0..<10 {
                let line = NSMenuItem()
                line.action = #selector(openWindow)
                line.target = self
                summary.addItem(line)
                trafficItems.append(line)
            }
            summary.addItem(.separator())
            add("Quit topp", to: summary, action: #selector(quit))
            summary.delegate = self
            monitor.onChange = { [weak self] in self?.updateStatusItem() }
            updateStatusItem()
        } else {
            openWindow()
        }
        monitor.start()
    }

    private func add(_ title: String, to menu: NSMenu, action: Selector, key: String = "") {
        menu.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
    }

    @objc func openWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSMakeRect(0, 0, 920, 520),
                             styleMask: [.titled, .resizable, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "topp · Network Ports"
            w.contentView = NSHostingView(rootView: PortWindow(monitor: monitor))
            w.setContentSize(NSSize(width: 920, height: 520))
            w.contentMinSize = NSSize(width: 800, height: 320)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func clickStatus() {
        guard let button = item?.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            updateSummary()
            summary.popUp(positioning: nil, at: NSPoint(x: 0, y: -3), in: button)
        } else {
            openWindow()
        }
    }

    func menuWillOpen(_ menu: NSMenu) { trackingMenu = true }
    func menuDidClose(_ menu: NSMenu) {
        trackingMenu = false
        menuOwners.removeAll()
    }

    private func updateSummary() {
        // Freeze the ranking while the menu is open. Fill vacancies at the end.
        let ranked = monitor.busiest
        let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
        var rows = menuOwners.compactMap { byID[$0] }
        let retained = Set(rows.map(\.id))
        rows += ranked.lazy.filter { !retained.contains($0.id) }.prefix(trafficItems.count - rows.count)
        menuOwners = rows.map(\.id)
        for (i, item) in trafficItems.enumerated() {
            item.isHidden = i >= rows.count
            if i < rows.count {
                let title = detail(rows[i])
                item.title = title.string
                item.attributedTitle = title
                item.image = ProcessArtwork.forRow(rows[i]).menuIcon
            }
        }
        if rows.isEmpty, let item = trafficItems.first {
            item.image = nil
            item.attributedTitle = nil
            item.title = monitor.rows.isEmpty ? monitor.status : "All ports are hidden"
            item.isHidden = false
        }
    }

    private func detail(_ row: PortRow) -> NSAttributedString {
        let title = NSMutableAttributedString(string: "\(row.id.port.label)   ")
        func append(_ value: String, field: PortRow.Field? = nil) {
            let highlight = field.map { row.changed.contains($0) } ?? false
            title.append(NSAttributedString(string: value, attributes: highlight ? [.backgroundColor: changeColor] : [:]))
        }
        append(row.process, field: .process)
        append(" (\(row.id.pid))   ↓ ")
        append(row.rxText, field: .rx)
        append("   ↑ ")
        append(row.txText, field: .tx)
        return title
    }

    private func updateStatusItem() {
        guard let button = item?.button else { return }
        let hint: String
        if let top = monitor.busiestPort {
            button.title = " \(top.port.label) · \(rate(top.total))"
            hint = "\(top.port.label)   ↓ \(rate(top.rx))   ↑ \(rate(top.tx))"
        } else {
            button.title = " —"
            hint = monitor.rows.contains(where: \.hasRate) ? "No traffic on visible ports" : monitor.status
        }
        button.toolTip = hint + "\nClick to open · Right-click for traffic"
        button.setAccessibilityLabel("topp · " + hint)
        if trackingMenu { updateSummary() }
    }

    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !menuMode }
}

struct LaunchError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// sudo shares the foreground process group for its password prompt. The menu
// process gets a separate session so closing the terminal cannot stop the GUI.
func spawn(_ arguments: [String], input: Int32? = nil, output: Int32? = nil, detached: Bool = false) throws -> pid_t {
    var actions: posix_spawn_file_actions_t?, attr: posix_spawnattr_t?
    func check(_ code: Int32) throws {
        if code != 0 { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
    }
    try check(posix_spawn_file_actions_init(&actions))
    defer { posix_spawn_file_actions_destroy(&actions) }
    try check(posix_spawnattr_init(&attr))
    defer { posix_spawnattr_destroy(&attr) }
    let flags = POSIX_SPAWN_CLOEXEC_DEFAULT | (detached ? POSIX_SPAWN_SETSID : 0)
    try check(posix_spawnattr_setflags(&attr, Int16(flags)))
    if let input {
        try check(posix_spawn_file_actions_adddup2(&actions, input, STDIN_FILENO))
    } else {
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
    }
    if let output {
        try check(posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO))
    } else {
        try check(posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0))
    }
    if detached {
        try check(posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO))
    } else {
        try check(posix_spawn_file_actions_addinherit_np(&actions, STDERR_FILENO))
    }
    let argv = arguments.map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    try check(posix_spawn(&pid, arguments[0], &actions, &attr, argv, environ))
    return pid
}

func runWindow(menuMode: Bool) {
    let app = NSApplication.shared
    app.setActivationPolicy(menuMode ? .accessory : .regular)
    let delegate = AppDelegate(menuMode: menuMode)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}

let usage = """
Usage: topp [-d]
  No options     Open the window. Closing it quits topp.
  -d             Show the busiest port and its total traffic rate in the menu bar.
                 Click to open the window. Right-click to view traffic or quit.
  -h, --help     Show this help.
"""
let args = Array(CommandLine.arguments.dropFirst())
do {
    if args == ["--help"] || args == ["-h"] { print(usage); exit(0) }
    if args == ["--menu-stream"], isatty(STDIN_FILENO) == 0 { runWindow(menuMode: true); exit(0) }
    guard args.isEmpty || args == ["-d"] else { throw LaunchError(usage) }
    guard geteuid() != 0 else { throw LaunchError("Run topp as your regular user. It requests sudo when needed.") }
    let input = try startCollector()
    if args == ["-d"] {
        guard let path = Bundle.main.executableURL?.path else { throw LaunchError("Could not find the topp executable.") }
        _ = try spawn([path, "--menu-stream"], input: input.fileDescriptor, detached: true)
        print("topp is running in the menu bar. Click to open the window, or right-click to view traffic or quit.")
    } else {
        guard dup2(input.fileDescriptor, STDIN_FILENO) >= 0 else { throw LaunchError("Could not open the nettop data stream.") }
        runWindow(menuMode: false)
    }
} catch {
    FileHandle.standardError.write(Data(("topp: " + error.localizedDescription + "\n").utf8))
    exit(1)
}
