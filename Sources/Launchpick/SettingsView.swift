import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models

enum ActionType: String, CaseIterable, Equatable {
    case openApp = "Open App"
    case openURL = "Open URL"
    case shellCommand = "Shell Command"
}

enum IconMode: String, CaseIterable, Equatable {
    case auto = "Auto-detect"
    case sfSymbol = "Symbol"
    case appIcon = "App Icon"
    case custom = "Custom Image"
}

struct EditableLauncher: Identifiable, Equatable {
    var id = UUID()
    var name: String = "New Item"
    var actionType: ActionType = .openApp
    var appName: String = ""
    var appArgs: String = ""
    var url: String = ""
    var shellCommand: String = ""
    var iconMode: IconMode = .auto
    var iconValue: String = ""

    static func from(_ config: ConfigLauncher) -> EditableLauncher {
        var l = EditableLauncher()
        l.name = config.name

        let exec = config.exec
        if let appName = extractAppName(from: exec) {
            l.actionType = .openApp
            l.appName = appName
            l.appArgs = extractAppArgs(from: exec, appName: appName)
        } else if exec.hasPrefix("open ") && (exec.contains("http://") || exec.contains("https://")) {
            l.actionType = .openURL
            l.url = extractURL(from: exec)
        } else {
            l.actionType = .shellCommand
            l.shellCommand = exec
        }

        if let icon = config.icon {
            if icon.hasPrefix("sf:") {
                l.iconMode = .sfSymbol
                l.iconValue = String(icon.dropFirst(3))
            } else if icon.hasSuffix(".app") {
                l.iconMode = .appIcon
                l.iconValue = icon
            } else if !icon.isEmpty {
                l.iconMode = .custom
                l.iconValue = icon
            }
        }

        return l
    }

    func toConfig() -> ConfigLauncher {
        let exec: String
        switch actionType {
        case .openApp:
            if appName.isEmpty {
                exec = ""
            } else if appArgs.isEmpty {
                exec = "open -a '\(appName)'"
            } else {
                exec = "open -a '\(appName)' '\(appArgs)'"
            }
        case .openURL:
            exec = url.isEmpty ? "" : "open '\(url)'"
        case .shellCommand:
            exec = shellCommand
        }

        let icon: String?
        switch iconMode {
        case .auto: icon = nil
        case .sfSymbol: icon = iconValue.isEmpty ? nil : "sf:\(iconValue)"
        case .appIcon: icon = iconValue.isEmpty ? nil : iconValue
        case .custom: icon = iconValue.isEmpty ? nil : iconValue
        }

        return ConfigLauncher(name: name, exec: exec, icon: icon)
    }

    func resolvedIcon() -> NSImage {
        switch iconMode {
        case .auto:
            return IconResolver.resolve(icon: nil, exec: toConfig().exec)
        case .sfSymbol:
            if !iconValue.isEmpty,
               let img = NSImage(systemSymbolName: iconValue, accessibilityDescription: nil) {
                return img
            }
        case .appIcon:
            if !iconValue.isEmpty {
                return NSWorkspace.shared.icon(forFile: iconValue)
            }
        case .custom:
            if let img = NSImage(contentsOfFile: iconValue) {
                return img
            }
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!
    }

    // MARK: Parsing

    private static func extractAppName(from exec: String) -> String? {
        let patterns = [
            #"open\s+(?:-\w\s+)*-a\s+'([^']+)'"#,
            #"open\s+(?:-\w\s+)*-a\s+"([^"]+)""#,
            #"open\s+(?:-\w\s+)*-a\s+(\S+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: exec, range: NSRange(exec.startIndex..., in: exec)),
                  let range = Range(match.range(at: 1), in: exec) else { continue }
            return String(exec[range])
        }
        return nil
    }

    private static func extractAppArgs(from exec: String, appName: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: appName)
        let patterns = [
            "open\\s+(?:-\\w\\s+)*-a\\s+'\(escaped)'\\s*",
            "open\\s+(?:-\\w\\s+)*-a\\s+\"\(escaped)\"\\s*",
            "open\\s+(?:-\\w\\s+)*-a\\s+\(escaped)\\s*",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: exec, range: NSRange(exec.startIndex..., in: exec)),
                  let range = Range(match.range, in: exec) else { continue }
            var args = String(exec[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes so the UI shows clean paths
            if (args.hasPrefix("'") && args.hasSuffix("'")) ||
               (args.hasPrefix("\"") && args.hasSuffix("\"")) {
                args = String(args.dropFirst().dropLast())
            }
            return args
        }
        return ""
    }

    private static func extractURL(from exec: String) -> String {
        let patterns = [
            #"open\s+'([^']+)'"#,
            #"open\s+"([^"]+)""#,
            #"open\s+(\S+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: exec, range: NSRange(exec.startIndex..., in: exec)),
                  let range = Range(match.range(at: 1), in: exec) else { continue }
            return String(exec[range])
        }
        return ""
    }
}

// MARK: - App Scanner

class AppScanner {
    static let shared = AppScanner()

    struct App: Identifiable {
        let id: String
        let name: String
        let path: String
        let icon: NSImage
    }

    lazy var apps: [App] = {
        var result: [App] = []
        var seen = Set<String>()
        let fm = FileManager.default
        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "\(NSHomeDirectory())/Applications",
        ]

        for basePath in searchPaths {
            guard let items = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for item in items.sorted() where item.hasSuffix(".app") {
                let fullPath = "\(basePath)/\(item)"
                let name = String(item.dropLast(4))
                guard seen.insert(name).inserted else { continue }
                let icon = NSWorkspace.shared.icon(forFile: fullPath)
                result.append(App(id: fullPath, name: name, path: fullPath, icon: icon))
            }
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()
}

// MARK: - Settings State

class SettingsState: ObservableObject {
    @Published var launchers: [EditableLauncher] = []
    @Published var selectedID: UUID?
    @Published var shortcut: String = "cmd+shift+space"
    @Published var switcherShortcut: String = "alt+tab"
    @Published var sameAppSwitcherShortcut: String = "alt+cmd+p"
    @Published var suppressSystemShortcut: Bool = false
    var columns: Int = 4

    var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return launchers.firstIndex(where: { $0.id == id })
    }

    var canMoveUp: Bool {
        guard let index = selectedIndex else { return false }
        return index > 0
    }

    var canMoveDown: Bool {
        guard let index = selectedIndex else { return false }
        return index < launchers.count - 1
    }

    func load() {
        let config = LaunchpickConfig.load()
        shortcut = config.shortcut
        switcherShortcut = config.switcherShortcut ?? "alt+tab"
        sameAppSwitcherShortcut = config.sameAppSwitcherShortcut ?? "alt+cmd+p"
        suppressSystemShortcut = config.suppressSystemShortcut ?? false
        columns = config.columns ?? 4
        launchers = config.launchers.map { EditableLauncher.from($0) }
        selectedID = launchers.first?.id
    }

    func save() {
        let config = LaunchpickConfig(
            shortcut: shortcut,
            switcherShortcut: switcherShortcut,
            sameAppSwitcherShortcut: sameAppSwitcherShortcut,
            suppressSystemShortcut: suppressSystemShortcut,
            columns: columns,
            launchers: launchers.map { $0.toConfig() }
        )
        LaunchpickConfig.save(config)
        NotificationCenter.default.post(name: Notification.Name("ReloadHotKey"), object: nil)
    }

    func addLauncher() {
        let new = EditableLauncher()
        launchers.append(new)
        selectedID = new.id
        save()
    }

    func removeSelected() {
        guard let id = selectedID,
              let index = launchers.firstIndex(where: { $0.id == id }) else { return }
        launchers.remove(at: index)
        if !launchers.isEmpty {
            selectedID = launchers[min(index, launchers.count - 1)].id
        } else {
            selectedID = nil
        }
        save()
    }

    func moveUp() {
        guard let index = selectedIndex, index > 0 else { return }
        launchers.swapAt(index, index - 1)
        save()
    }

    func moveDown() {
        guard let index = selectedIndex, index < launchers.count - 1 else { return }
        launchers.swapAt(index, index + 1)
        save()
    }
}

// MARK: - Launch at Login

enum LaunchAtLogin {
    private static let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/com.custom.launchpick.plist"

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.custom.launchpick</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/Applications/Launchpick.app/Contents/MacOS/Launchpick</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """
            let dir = (plistPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["load", plistPath]
                try? process.run()
                process.waitUntilExit()
            }
        } else {
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["unload", plistPath]
                try? process.run()
                process.waitUntilExit()
                try? FileManager.default.removeItem(atPath: plistPath)
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        TabView {
            LaunchersSettingsTab(state: state)
                .tabItem { Label("Launchers", systemImage: "square.grid.2x2") }

            GeneralSettingsTab(state: state, launchAtLogin: $launchAtLogin)
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(minWidth: 650, minHeight: 400)
    }
}

// MARK: - Shortcut Recorder

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: String
    var onSave: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.shortcut = shortcut
        view.onChange = { newShortcut in
            shortcut = newShortcut
            onSave()
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.shortcut = shortcut
        nsView.needsDisplay = true
    }
}

class ShortcutRecorderNSView: NSView {
    var shortcut: String = ""
    var onChange: ((String) -> Void)?
    private var isRecording = false
    private var shortcutBeforeRecording: String = ""
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var keyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 200, height: 28)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        } else if isHovered {
            NSColor.controlBackgroundColor.setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        let borderColor = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        borderColor.setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            text = "Press shortcut\u{2026}"
            color = .controlAccentColor
        } else {
            text = displayString(for: shortcut)
            color = .labelColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let size = attrStr.size()
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        attrStr.draw(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            cancelRecording()
            return
        }
        isRecording = true
        shortcutBeforeRecording = shortcut
        window?.makeFirstResponder(self)
        needsDisplay = true
        installKeyMonitor()
    }

    override func keyDown(with event: NSEvent) {
        guard !isRecording else { return }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { cancelRecording() }
        return super.resignFirstResponder()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            // Escape cancels recording
            if event.keyCode == 53 {
                self.cancelRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isFunctionKey = flags.contains(.function) || self.keyName(for: event.keyCode)?.hasPrefix("f") == true
            let hasModifier = !flags.intersection([.command, .control, .option, .shift]).isEmpty

            guard hasModifier || isFunctionKey else { return nil }

            var parts: [String] = []
            if flags.contains(.command) { parts.append("cmd") }
            if flags.contains(.control) { parts.append("ctrl") }
            if flags.contains(.option) { parts.append("alt") }
            if flags.contains(.shift) { parts.append("shift") }

            if let keyName = self.keyName(for: event.keyCode) {
                parts.append(keyName)
            } else if let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty {
                parts.append(chars)
            } else {
                return nil
            }

            self.isRecording = false
            self.shortcut = parts.joined(separator: "+")
            self.onChange?(self.shortcut)
            self.needsDisplay = true
            self.removeKeyMonitor()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func cancelRecording() {
        isRecording = false
        shortcut = shortcutBeforeRecording
        needsDisplay = true
        removeKeyMonitor()
    }

    private func keyName(for keyCode: UInt16) -> String? {
        let map: [UInt16: String] = [
            49: "space", 36: "return", 48: "tab", 51: "delete", 53: "escape",
            123: "left", 124: "right", 125: "down", 126: "up", 50: "`",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
            98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
            105: "f13", 107: "f14", 113: "f15", 106: "f16", 64: "f17", 79: "f18", 80: "f19",
        ]
        return map[keyCode]
    }

    private func displayString(for shortcut: String) -> String {
        shortcut.split(separator: "+").map { part in
            switch part.lowercased() {
            case "cmd", "command": return "\u{2318}"
            case "ctrl", "control": return "\u{2303}"
            case "alt", "opt", "option": return "\u{2325}"
            case "shift": return "\u{21E7}"
            case "space": return "Space"
            case "tab": return "\u{21E5}"
            case "return", "enter": return "\u{21A9}"
            case "delete": return "\u{232B}"
            case "escape": return "\u{238B}"
            case "`", "~": return "`"
            case "up": return "\u{2191}"
            case "down": return "\u{2193}"
            case "left": return "\u{2190}"
            case "right": return "\u{2192}"
            default: return part.uppercased()
            }
        }.joined(separator: " ")
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @ObservedObject var state: SettingsState
    @Binding var launchAtLogin: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLogin.setEnabled(newValue)
                    }
            }

            Section("Launchpick Shortcut") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    ShortcutRecorderView(shortcut: $state.shortcut) {
                        state.save()
                    }
                    .frame(width: 200, height: 28)
                }
                Toggle("Suppress system shortcut (e.g. Spotlight)", isOn: $state.suppressSystemShortcut)
                    .onChange(of: state.suppressSystemShortcut) { _ in
                        state.save()
                    }
                Text("Click to record a new shortcut. Enable suppress if your shortcut conflicts with a system shortcut like Spotlight.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Window Switcher") {
                HStack {
                    Text("All Windows")
                    Spacer()
                    ShortcutRecorderView(shortcut: $state.switcherShortcut) {
                        state.save()
                    }
                    .frame(width: 200, height: 28)
                }
                HStack {
                    Text("Cycle Same App")
                    Spacer()
                    ShortcutRecorderView(shortcut: $state.sameAppSwitcherShortcut) {
                        state.save()
                    }
                    .frame(width: 200, height: 28)
                }
                Text("All Windows: hold modifier + press key to cycle, release to activate.\nCycle Same App: each press brings the next window of the current app to front.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Launchers Settings Tab

struct LaunchersSettingsTab: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                List(selection: $state.selectedID) {
                    ForEach(state.launchers) { launcher in
                        HStack(spacing: 8) {
                            Image(nsImage: launcher.resolvedIcon())
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                            Text(launcher.name.isEmpty ? "Untitled" : launcher.name)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .tag(launcher.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    ControlGroup {
                        Button(action: state.addLauncher) {
                            Image(systemName: "plus")
                        }
                        Button(action: state.removeSelected) {
                            Image(systemName: "minus")
                        }
                        .disabled(state.selectedID == nil)
                    }
                    .frame(width: 72)

                    Spacer()

                    ControlGroup {
                        Button(action: state.moveUp) {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(!state.canMoveUp)
                        Button(action: state.moveDown) {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(!state.canMoveDown)
                    }
                    .frame(width: 72)
                }
                .padding(8)
            }
            .frame(width: 220)

            Divider()

            // Detail
            if let index = state.selectedIndex, index < state.launchers.count {
                LauncherDetailView(
                    launcher: $state.launchers[index],
                    state: state
                )
                .id(state.selectedID)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select an item to edit")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Detail View

struct LauncherDetailView: View {
    @Binding var launcher: EditableLauncher
    let state: SettingsState
    @State private var showIconPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Icon + Name
                HStack(alignment: .top, spacing: 16) {
                    Button(action: { showIconPicker.toggle() }) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(nsImage: launcher.resolvedIcon())
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(14)

                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.accentColor)
                                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                                .offset(x: 4, y: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showIconPicker) {
                        IconPickerView(launcher: $launcher, isPresented: $showIconPicker)
                    }
                    .help("Click to change icon")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Name", text: $launcher.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                    }
                }

                Divider()

                // Action type
                VStack(alignment: .leading, spacing: 8) {
                    Text("Action")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $launcher.actionType) {
                        ForEach(ActionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Action-specific fields
                VStack(alignment: .leading, spacing: 12) {
                    switch launcher.actionType {
                    case .openApp:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Application")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $launcher.appName) {
                                Text("Choose an app...").tag("")
                                ForEach(AppScanner.shared.apps) { app in
                                    Text(app.name).tag(app.name)
                                }
                            }
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Arguments (optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("e.g. ~/projects/my-app", text: $launcher.appArgs)
                                .textFieldStyle(.roundedBorder)
                        }

                    case .openURL:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URL")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("https://example.com", text: $launcher.url)
                                .textFieldStyle(.roundedBorder)
                        }

                    case .shellCommand:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shell Command")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("/path/to/script.sh", text: $launcher.shellCommand)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                // Icon mode info
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text(iconModeDescription)
                        .font(.caption)
                }
                .foregroundColor(.secondary)

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: launcher) { _ in
            state.save()
        }
        .onChange(of: launcher.appName) { newName in
            if (launcher.name == "New Item" || launcher.name.isEmpty) && !newName.isEmpty {
                launcher.name = newName
            }
        }
    }

    var iconModeDescription: String {
        switch launcher.iconMode {
        case .auto: return "Icon auto-detected from command"
        case .sfSymbol: return "Using SF Symbol: \(launcher.iconValue)"
        case .appIcon: return "Using app icon"
        case .custom: return "Using custom image"
        }
    }
}
