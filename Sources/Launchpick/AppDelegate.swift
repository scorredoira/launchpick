import Carbon
import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: LaunchpickPanel!
    private var state = LaunchpickState()
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var settingsWindow: NSWindow?
    private var isShowingPanel = false

    // Window switcher properties
    private var switcherPanel: WindowSwitcherPanel!
    private var switcherState = WindowSwitcherState()
    private var isSwitcherVisible = false
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    // Hotkey IDs
    private let launchpickHotKeyID: UInt32 = 1

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

        // Register launchpick hotkey
        let config = LaunchpickConfig.load()
        let (keyCode, modifiers) = LaunchpickConfig.parseShortcut(config.shortcut)
        HotKeyManager.shared.register(id: launchpickHotKeyID, keyCode: keyCode, modifiers: modifiers) { [weak self] in
            DispatchQueue.main.async {
                self?.handleLaunchpickHotKey()
            }
        }

        // Reload launchpick hotkey when shortcut changes in settings
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ReloadHotKey"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadLaunchpickHotKey()
        }

        // Request accessibility permission (shows system dialog if not granted)
        // and install CGEventTap for Option+Tab interception
        AccessibilityHelper.checkAndRequestPermission()
        setupEventTap()
    }

    private func reloadLaunchpickHotKey() {
        HotKeyManager.shared.unregister(id: launchpickHotKeyID)
        let config = LaunchpickConfig.load()
        let (keyCode, modifiers) = LaunchpickConfig.parseShortcut(config.shortcut)
        HotKeyManager.shared.register(id: launchpickHotKeyID, keyCode: keyCode, modifiers: modifiers) { [weak self] in
            DispatchQueue.main.async {
                self?.handleLaunchpickHotKey()
            }
        }
    }

    // MARK: - Launchpick hotkey handler (cross-feature)

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

        NotificationCenter.default.addObserver(
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
        state.columns = config.columns ?? 4
    }

    @objc func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // Hide switcher if visible
        if isSwitcherVisible {
            hideSwitcher()
        }

        isShowingPanel = true
        previousApp = NSWorkspace.shared.frontmostApplication

        reloadLaunchers()
        state.searchText = ""
        state.selectedIndex = 0
        state.focusTrigger.toggle()

        // Size
        let panelWidth: CGFloat = 720
        let columns = state.columns
        let itemCount = max(state.launchers.count, 1)
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        let panelHeight: CGFloat = 56 + CGFloat(rows) * 172 + 24

        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

        // Position centered, upper portion of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.minY + screenFrame.height * 0.65
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isShowingPanel = false
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Escape closes the panel
            if event.keyCode == 53 {
                self.hidePanel()
                return nil
            }

            // Cmd+V/C/X/A for borderless window
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

            // Arrow keys for grid navigation
            let count = self.state.filteredLaunchers.count
            let columns = self.state.columns
            guard count > 0 else { return event }

            switch event.keyCode {
            case 126: // Up
                let newIndex = self.state.selectedIndex - columns
                if newIndex >= 0 { self.state.selectedIndex = newIndex }
                return nil
            case 125: // Down
                let newIndex = self.state.selectedIndex + columns
                if newIndex < count { self.state.selectedIndex = newIndex }
                return nil
            case 123: // Left
                if self.state.selectedIndex > 0 { self.state.selectedIndex -= 1 }
                return nil
            case 124: // Right
                if self.state.selectedIndex < count - 1 { self.state.selectedIndex += 1 }
                return nil
            case 36: // Enter - launch selected item
                let index = max(0, min(self.state.selectedIndex, count - 1))
                self.state.onLaunch?(self.state.filteredLaunchers[index])
                return nil
            default:
                return event
            }
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)

        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        // Return focus to previously active app
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

    // MARK: - CGEventTap for Option+Tab

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
            // Retry every 2 seconds until permission is granted
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
        NSLog("Launchpick: Event tap installed successfully")
    }

    private func handleEventTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the tap gets disabled by the system, re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Handle flagsChanged — detect Option release
        if type == .flagsChanged {
            if isSwitcherVisible && !flags.contains(.maskAlternate) {
                DispatchQueue.main.async { [weak self] in
                    self?.activateSelectedWindow()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // Handle keyDown
        if type == .keyDown {
            let hasOption = flags.contains(.maskAlternate)
            let hasShift = flags.contains(.maskShift)
            let hasCmd = flags.contains(.maskCommand)
            let hasCtrl = flags.contains(.maskControl)

            // Option+Tab (no Cmd, no Ctrl)
            if keyCode == 48 && hasOption && !hasCmd && !hasCtrl {
                if hasShift {
                    DispatchQueue.main.async { [weak self] in
                        self?.switcherPrevious()
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.switcherNext()
                    }
                }
                return nil // Swallow the event
            }

            // Option+Escape — cancel switcher
            if keyCode == 53 && hasOption && isSwitcherVisible {
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
        if !isSwitcherVisible {
            showSwitcher()
            if switcherState.windows.count > 1 {
                switcherState.selectedIndex = 1
            }
        } else {
            switcherState.selectNext()
        }
    }

    private func switcherPrevious() {
        if !isSwitcherVisible {
            showSwitcher()
            if switcherState.windows.count > 1 {
                switcherState.selectedIndex = switcherState.windows.count - 1
            }
        } else {
            switcherState.selectPrevious()
        }
    }

    private func showSwitcher() {
        // Hide launchpick if visible
        if panel.isVisible {
            hidePanel()
        }

        // Check accessibility permission
        guard AccessibilityHelper.checkAndRequestPermission() else {
            NSLog("Launchpick: Accessibility permission not granted")
            return
        }

        // Enumerate windows
        let windows = WindowEnumerator.enumerate()
        guard !windows.isEmpty else { return }

        switcherState.windows = windows
        switcherState.selectedIndex = 0

        // Size the panel (148 item + 12 spacing = 160 per item)
        let itemCount = min(windows.count, 10)
        let panelWidth = min(CGFloat(itemCount) * 160 + 32, NSScreen.main?.frame.width ?? 800 * 0.8)
        let panelHeight: CGFloat = 230

        switcherPanel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.midY - panelHeight / 2
            switcherPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        switcherPanel.orderFront(nil)
        isSwitcherVisible = true
    }

    private func activateSelectedWindow() {
        guard let window = switcherState.selectedWindow else {
            hideSwitcher()
            return
        }

        hideSwitcher()

        // Unminimize if needed
        if window.isMinimized {
            AXUIElementSetAttributeValue(
                window.axWindow,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
        }

        // Raise the window
        AXUIElementPerformAction(window.axWindow, kAXRaiseAction as CFString)

        // Activate the app
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [])
        }
    }

    private func hideSwitcher() {
        guard isSwitcherVisible else { return }
        isSwitcherVisible = false
        switcherPanel.orderOut(nil)
    }
}
