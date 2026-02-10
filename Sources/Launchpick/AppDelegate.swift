import Carbon
import Cocoa
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: LaunchpickPanel!
    private var state = LaunchpickState()
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var searchSubscription: AnyCancellable?
    private var previousApp: NSRunningApplication?
    private var settingsWindow: NSWindow?
    private var settingsCloseObserver: NSObjectProtocol?
    private var isShowingPanel = false

    // Window switcher properties
    private var switcherPanel: WindowSwitcherPanel!
    private var switcherState = WindowSwitcherState()
    private var isSwitcherVisible = false
    private var switcherPendingAdvances = 0
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    // Hotkey IDs
    private let launchpickHotKeyID: UInt32 = 1

    // Window switcher shortcut (parsed from config)
    // These are read from the event tap thread — use volatile-style access
    private var switcherKeyCode: Int64 = 48
    private var switcherModifiers = CGEventFlags.maskCommand
    private var switcherHoldModifier = CGEventFlags.maskCommand

    // Launcher shortcut (parsed for event tap suppression of system shortcuts)
    private var launcherKeyCode: Int64 = 49
    private var launcherModifiers = CGEventFlags.maskCommand
    private var suppressSystemShortcut = false

    // Same-app window cycling hotkey
    private let sameAppHotKeyID: UInt32 = 2
    private let sameAppVisibleHotKeyID: UInt32 = 3

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupPanel()
        setupSwitcherPanel()
        reloadLaunchers()

        state.onLaunch = { [weak self] item in
            self?.launch(item)
        }
        state.onDismiss = { [weak self] in
            self?.hidePanel()
        }

        // Load shortcuts from config
        let config = LaunchpickConfig.load()
        loadSwitcherShortcut(from: config)
        loadLauncherShortcut(from: config)
        registerSameAppHotKey(from: config)
        registerSameAppVisibleHotKey(from: config)
        applySpotlightShortcut(from: config)

        // Register launchpick hotkey
        let (keyCode, modifiers) = LaunchpickConfig.parseShortcut(config.shortcut)
        HotKeyManager.shared.register(id: launchpickHotKeyID, keyCode: keyCode, modifiers: modifiers) { [weak self] in
            DispatchQueue.main.async {
                self?.handleLaunchpickHotKey()
            }
        }

        // Reload hotkeys when shortcuts change in settings
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ReloadHotKey"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let config = LaunchpickConfig.load()
            self?.reloadLaunchpickHotKey(from: config)
            self?.loadSwitcherShortcut(from: config)
            self?.loadLauncherShortcut(from: config)
            self?.registerSameAppHotKey(from: config)
            self?.registerSameAppVisibleHotKey(from: config)
            self?.applySpotlightShortcut(from: config)
        }

        // Pre-load system apps in background so first search doesn't lag
        DispatchQueue.global(qos: .utility).async {
            _ = AppScanner.shared.apps
        }

        // Request accessibility permission and install event tap
        if !AccessibilityHelper.isTrusted {
            // Try the system prompt first
            AccessibilityHelper.checkAndRequestPermission()

            // If still not trusted, show our own alert with a direct link
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !AccessibilityHelper.isTrusted {
                    AccessibilityHelper.showAccessibilityAlert()
                }
            }
        }
        setupEventTap()
    }

    private func reloadLaunchpickHotKey(from config: LaunchpickConfig) {
        HotKeyManager.shared.unregister(id: launchpickHotKeyID)
        let (keyCode, modifiers) = LaunchpickConfig.parseShortcut(config.shortcut)
        HotKeyManager.shared.register(id: launchpickHotKeyID, keyCode: keyCode, modifiers: modifiers) { [weak self] in
            DispatchQueue.main.async {
                self?.handleLaunchpickHotKey()
            }
        }
    }

    private func loadLauncherShortcut(from config: LaunchpickConfig) {
        let parsed = LaunchpickConfig.parseSwitcherShortcut(config.shortcut)
        launcherKeyCode = parsed.keyCode
        launcherModifiers = parsed.modifiers
        suppressSystemShortcut = config.suppressSystemShortcut ?? false
    }

    private func applySpotlightShortcut(from config: LaunchpickConfig) {
        if let shortcut = config.spotlightShortcut, !shortcut.isEmpty {
            SpotlightShortcutManager.applyShortcut(shortcut)
        }
    }

    private func loadSwitcherShortcut(from config: LaunchpickConfig) {
        let shortcut = config.switcherShortcut ?? "alt+tab"
        let parsed = LaunchpickConfig.parseSwitcherShortcut(shortcut)
        switcherKeyCode = parsed.keyCode
        switcherModifiers = parsed.modifiers
        switcherHoldModifier = parsed.holdModifier
    }

    private func registerSameAppHotKey(from config: LaunchpickConfig) {
        HotKeyManager.shared.unregister(id: sameAppHotKeyID)
        let shortcut = config.sameAppSwitcherShortcut ?? "alt+cmd+p"
        let (keyCode, modifiers) = LaunchpickConfig.parseShortcut(shortcut)
        HotKeyManager.shared.register(id: sameAppHotKeyID, keyCode: keyCode, modifiers: modifiers) { [weak self] in
            DispatchQueue.main.async {
                self?.cycleAppWindows()
            }
        }
    }

    private func cycleAppWindows() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier

        DispatchQueue.global(qos: .userInteractive).async {
            let allWindows = WindowEnumerator.enumerate()
            let appWindows = allWindows.filter { $0.pid == pid }
            guard appWindows.count > 1 else { return }

            let next = appWindows.last!

            if next.isMinimized {
                AXUIElementSetAttributeValue(
                    next.axWindow,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanFalse
                )
            }

            AXUIElementPerformAction(next.axWindow, kAXRaiseAction as CFString)

            DispatchQueue.main.async {
                frontApp.activate(options: [])
            }
        }
    }

    private func registerSameAppVisibleHotKey(from config: LaunchpickConfig) {
        HotKeyManager.shared.unregister(id: sameAppVisibleHotKeyID)
        let sameAppShortcut = config.sameAppSwitcherShortcut ?? "alt+cmd+p"
        let shortcut = config.sameAppVisibleShortcut ?? LaunchpickConfig.deriveVisibleShortcut(from: sameAppShortcut)
        let (keyCode, modifiers) = LaunchpickConfig.parseShortcut(shortcut)
        HotKeyManager.shared.register(id: sameAppVisibleHotKeyID, keyCode: keyCode, modifiers: modifiers) { [weak self] in
            DispatchQueue.main.async {
                self?.cycleAppWindowsVisible()
            }
        }
    }

    private func cycleAppWindowsVisible() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier

        DispatchQueue.global(qos: .userInteractive).async {
            let allWindows = WindowEnumerator.enumerate()
            let appWindows = allWindows.filter { $0.pid == pid && !$0.isMinimized }
            guard appWindows.count > 1 else { return }

            let next = appWindows.last!

            AXUIElementPerformAction(next.axWindow, kAXRaiseAction as CFString)

            DispatchQueue.main.async {
                frontApp.activate(options: [])
            }
        }
    }

    // MARK: - Launchpick hotkey handler

    private func handleLaunchpickHotKey() {
        if isSwitcherVisible {
            hideSwitcher()
        }
        togglePanel()
    }

    // MARK: - Menu setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "🚀"
        }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "Show Launchpick", action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let editItem = NSMenuItem(title: "Edit Config File...", action: #selector(editConfig), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Launchpick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        hidePanel()
        hideSwitcher()

        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsState = SettingsState()
        settingsState.load()

        let settingsView = SettingsView(state: settingsState)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Launchpick Settings"
        window.minSize = NSSize(width: 650, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let old = settingsCloseObserver {
            NotificationCenter.default.removeObserver(old)
        }
        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
        }

        settingsWindow = window
    }

    @objc private func editConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: LaunchpickConfig.configPath))
    }

    // MARK: - Launchpick panel

    private func setupPanel() {
        panel = LaunchpickPanel()

        let hostingView = NSHostingView(rootView: ContentView(state: state))
        panel.contentView = hostingView

        // Dismiss when panel loses focus
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.isShowingPanel else { return }
            self.hidePanel()
        }
    }

    private func reloadLaunchers() {
        let config = LaunchpickConfig.load()
        state.launchers = config.launchers.map { configItem in
            LaunchpickItem(
                name: configItem.name,
                exec: configItem.exec,
                icon: IconResolver.resolve(icon: configItem.icon, exec: configItem.exec)
            )
        }
        state.columns = max(1, config.columns ?? 4)
    }

    @objc func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        if isSwitcherVisible {
            hideSwitcher()
        }

        isShowingPanel = true
        previousApp = NSWorkspace.shared.frontmostApplication

        reloadLaunchers()
        state.searchText = ""
        state.selectedIndex = 0
        state.focusTrigger.toggle()

        resizePanelToFit()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Resize panel dynamically as search text changes
        searchSubscription = state.$searchText
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizePanelToFit()
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isShowingPanel = false
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if event.keyCode == 53 {
                self.hidePanel()
                return nil
            }

            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "v":
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    return nil
                case "c":
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    return nil
                case "x":
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                    return nil
                case "a":
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    return nil
                default:
                    break
                }
            }

            let launcherCount = self.state.filteredLaunchers.count
            let systemCount = min(self.state.filteredSystemApps.count, 8)
            let totalCount = launcherCount + systemCount
            let columns = self.state.columns
            guard totalCount > 0 else { return event }
            let idx = self.state.selectedIndex
            let inGrid = idx < launcherCount

            switch event.keyCode {
            case 126: // Up
                if inGrid {
                    let newIndex = idx - columns
                    if newIndex >= 0 { self.state.selectedIndex = newIndex }
                } else {
                    let listPos = idx - launcherCount
                    if listPos > 0 {
                        self.state.selectedIndex -= 1
                    } else if launcherCount > 0 {
                        self.state.selectedIndex = launcherCount - 1
                    }
                }
                return nil
            case 125: // Down
                if inGrid {
                    let newIndex = idx + columns
                    if newIndex < launcherCount {
                        self.state.selectedIndex = newIndex
                    } else if systemCount > 0 {
                        self.state.selectedIndex = launcherCount
                    }
                } else {
                    if idx < totalCount - 1 { self.state.selectedIndex += 1 }
                }
                return nil
            case 123: // Left
                if inGrid && idx > 0 { self.state.selectedIndex -= 1 }
                return nil
            case 124: // Right
                if inGrid && idx < launcherCount - 1 { self.state.selectedIndex += 1 }
                return nil
            case 36: // Enter
                if inGrid {
                    let i = max(0, min(idx, launcherCount - 1))
                    self.state.onLaunch?(self.state.filteredLaunchers[i])
                } else {
                    let i = idx - launcherCount
                    let apps = self.state.filteredSystemApps
                    if i >= 0 && i < apps.count {
                        self.state.onLaunch?(apps[i])
                    }
                }
                return nil
            default:
                return event
            }
        }
    }

    private func resizePanelToFit() {
        let panelWidth: CGFloat = 720
        let columns = state.columns
        let launcherCount = state.filteredLaunchers.count
        let systemCount = min(state.filteredSystemApps.count, 8)

        // Search bar: top padding 16 + bar ~44 + bottom padding 16
        var contentHeight: CGFloat = 76

        // Launcher grid
        if launcherCount > 0 {
            let rows = Int(ceil(Double(launcherCount) / Double(columns)))
            contentHeight += CGFloat(rows) * 172
        }

        // System apps list
        if systemCount > 0 {
            if launcherCount > 0 {
                contentHeight += 12 // divider
            }
            contentHeight += CGFloat(systemCount) * 46
        }

        // "No matches" placeholder
        if launcherCount == 0 && systemCount == 0 {
            contentHeight += 80
        }

        // Bottom padding
        contentHeight += 16

        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let panelHeight = min(contentHeight, screenHeight * 0.85)

        let currentFrame = panel.frame
        if panel.isVisible && currentFrame.height > 0 {
            // Keep top edge fixed — only grow/shrink downward
            let top = currentFrame.origin.y + currentFrame.size.height
            panel.setFrame(NSRect(x: currentFrame.origin.x, y: top - panelHeight, width: panelWidth, height: panelHeight), display: true)
        } else {
            // Initial positioning: center on screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - panelWidth / 2
                let y = screenFrame.midY - panelHeight / 2 + screenFrame.height * 0.1
                panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
            } else {
                panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
            }
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        searchSubscription = nil

        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        if let prev = previousApp, prev != NSRunningApplication.current {
            prev.activate(options: [])
        }
        previousApp = nil
    }

    private func launch(_ item: LaunchpickItem) {
        hidePanel()
        let home = NSHomeDirectory()
        let exec = item.exec
            .replacingOccurrences(of: "'~/", with: "'\(home)/")
            .replacingOccurrences(of: "\"~/", with: "\"\(home)/")
            .replacingOccurrences(of: " ~/", with: " \(home)/")
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", exec]
            process.environment = ProcessInfo.processInfo.environment
            try? process.run()
        }
    }

    // MARK: - Window Switcher

    private func setupSwitcherPanel() {
        switcherPanel = WindowSwitcherPanel()

        let hostingView = NSHostingView(rootView: WindowSwitcherView(state: switcherState))
        switcherPanel.contentView = hostingView
    }

    // MARK: - CGEventTap (runs on main run loop)

    private var eventTapRetryTimer: Timer?

    private func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return delegate.handleEventTap(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("Launchpick: Failed to create event tap. Waiting for Accessibility permission...")
            if eventTapRetryTimer == nil {
                eventTapRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    if AXIsProcessTrusted() {
                        self?.eventTapRetryTimer?.invalidate()
                        self?.eventTapRetryTimer = nil
                        self?.setupEventTap()
                    }
                }
            }
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Launchpick: Event tap installed")
    }

    // Event tap callback — runs on main run loop.
    // Keep it minimal. All heavy work (AX operations) dispatched to background.
    private func handleEventTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .flagsChanged {
            if isSwitcherVisible && !flags.contains(switcherHoldModifier) {
                DispatchQueue.main.async { [weak self] in
                    self?.activateSelectedWindow()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let currentMods = flags.intersection([.maskCommand, .maskAlternate, .maskControl])
            let switcherMods = switcherModifiers.subtracting(.maskShift)

            if keyCode == switcherKeyCode && currentMods == switcherMods {
                if flags.contains(.maskShift) {
                    DispatchQueue.main.async { [weak self] in
                        self?.switcherPrevious()
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.switcherNext()
                    }
                }
                return nil
            }

            // Launcher shortcut — suppress to prevent system shortcut (e.g. Spotlight)
            let fullMods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            let targetLauncherMods = launcherModifiers.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            if suppressSystemShortcut && keyCode == launcherKeyCode && fullMods == targetLauncherMods {
                DispatchQueue.main.async { [weak self] in
                    self?.handleLaunchpickHotKey()
                }
                return nil
            }

            if keyCode == 53 && isSwitcherVisible && flags.contains(switcherHoldModifier) {
                DispatchQueue.main.async { [weak self] in
                    self?.hideSwitcher()
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Switcher actions

    private func switcherNext() {
        if isSwitcherVisible {
            switcherState.selectNext()
        } else {
            switcherPendingAdvances += 1
            if switcherPendingAdvances == 1 {
                showSwitcher()
            }
        }
    }

    private func switcherPrevious() {
        if isSwitcherVisible {
            switcherState.selectPrevious()
        } else {
            switcherPendingAdvances -= 1
            if switcherPendingAdvances == -1 {
                showSwitcher()
            }
        }
    }

    private func showSwitcher() {
        if panel.isVisible {
            hidePanel()
        }

        guard AXIsProcessTrusted() else {
            switcherPendingAdvances = 0
            return
        }

        // Enumerate windows off the main thread
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let windows = WindowEnumerator.enumerate()
            guard !windows.isEmpty else {
                DispatchQueue.main.async { self?.switcherPendingAdvances = 0 }
                return
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.switcherState.windows = windows

                // Apply all pending advances (handles rapid Tab presses during async load)
                let pending = self.switcherPendingAdvances
                self.switcherPendingAdvances = 0

                if pending > 0 {
                    self.switcherState.selectedIndex = min(pending, windows.count - 1)
                } else if pending < 0 {
                    self.switcherState.selectedIndex = max(windows.count + pending, 0)
                } else {
                    self.switcherState.selectedIndex = 0
                }

                let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                let maxPanelWidth = screenFrame.width * 0.9
                let maxColumns = max(1, Int((maxPanelWidth - 32) / 160))
                let columns = min(maxColumns, windows.count)
                let rows = Int(ceil(Double(windows.count) / Double(columns)))

                self.switcherState.columns = columns

                let panelWidth = CGFloat(columns) * 160 + 32
                // 70 = top padding (12) + scroll padding (16) + info area (~42)
                let panelHeight = min(70 + CGFloat(rows) * 160, screenFrame.height * 0.85)

                self.switcherPanel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

                let x = screenFrame.midX - panelWidth / 2
                let y = screenFrame.midY - panelHeight / 2
                self.switcherPanel.setFrameOrigin(NSPoint(x: x, y: y))

                self.switcherPanel.orderFront(nil)
                self.isSwitcherVisible = true
            }
        }
    }

    private func activateSelectedWindow() {
        guard isSwitcherVisible else { return }

        let window = switcherState.selectedWindow

        // Hide switcher IMMEDIATELY so no more flagsChanged events trigger this
        hideSwitcher()

        guard let window = window else { return }

        // Do ALL AX operations off the main thread.
        // AXUIElement calls can block for seconds if the target app is unresponsive.
        let pid = window.pid
        let axWindow = window.axWindow
        let isMinimized = window.isMinimized

        DispatchQueue.global(qos: .userInteractive).async {
            if isMinimized {
                AXUIElementSetAttributeValue(
                    axWindow,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanFalse
                )
            }

            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)

            DispatchQueue.main.async {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: [])
                }
            }
        }
    }

    private func hideSwitcher() {
        guard isSwitcherVisible else { return }
        isSwitcherVisible = false
        switcherPanel.orderOut(nil)
    }
}
