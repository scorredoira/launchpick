import Cocoa
import SwiftUI

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let appIcon: NSImage
    let pid: pid_t
    let isMinimized: Bool
    var axWindow: AXUIElement?
    var visibleCount: Int = 0
    var minimizedCount: Int = 0

    func resolveAXWindow() -> AXUIElement? {
        if let ax = axWindow { return ax }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 1.0)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return nil }
        for ax in axWindows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(ax, &wid) == .success && wid == id {
                return ax
            }
        }
        return nil
    }
}

class WindowSwitcherState: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex: Int = 0
    @Published var columns: Int = 10
    @Published var groupByApp: Bool = false

    var selectedWindow: WindowInfo? {
        guard selectedIndex >= 0, selectedIndex < windows.count else { return nil }
        return windows[selectedIndex]
    }

    func selectNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    func selectPrevious() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
    }
}

// Private API to get CGWindowID from AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowEnumerator {

    // MARK: - Shared helpers

    private static func zOrderMap() -> [CGWindowID: Int] {
        guard let cgWindowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }
        var zOrder: [CGWindowID: Int] = [:]
        for (index, info) in cgWindowList.enumerated() {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            zOrder[windowID] = index
        }
        return zOrder
    }

    private static func appIcon(for app: NSRunningApplication) -> NSImage {
        app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
    }

    private static func readWindowInfo(from axWindow: AXUIElement, appName: String, appIcon: NSImage, pid: pid_t) -> WindowInfo? {
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""
        guard !title.isEmpty else { return nil }

        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
        let isMinimized = (minimizedRef as? Bool) ?? false

        var windowID: CGWindowID = 0
        let axErr = _AXUIElementGetWindow(axWindow, &windowID)
        let finalID: CGWindowID = (axErr == .success && windowID != 0) ? windowID : CGWindowID(arc4random())

        return WindowInfo(
            id: finalID, title: title, appName: appName, appIcon: appIcon,
            pid: pid, isMinimized: isMinimized, axWindow: axWindow
        )
    }

    // MARK: - Fast enumeration (CG only, no AX)

    /// Returns visible windows instantly using CGWindowList. axWindow is nil — resolve on demand.
    static func enumerateFast() -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        guard let cgWindowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var appIcons: [pid_t: (name: String, icon: NSImage)] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            appIcons[app.processIdentifier] = (app.localizedName ?? "Unknown", appIcon(for: app))
        }

        var results: [WindowInfo] = []

        for info in cgWindowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  let appInfo = appIcons[pid] else {
                continue
            }

            let cgTitle = info[kCGWindowName as String] as? String ?? ""
            let title = cgTitle.isEmpty ? appInfo.name : cgTitle

            results.append(WindowInfo(
                id: windowID, title: title, appName: appInfo.name, appIcon: appInfo.icon,
                pid: pid, isMinimized: false, axWindow: nil
            ))
        }

        return results
    }

    // MARK: - Grouping

    static func groupByApplication(_ windows: [WindowInfo]) -> [WindowInfo] {
        let grouped = Dictionary(grouping: windows, by: { $0.pid })

        // Preserve Z-order: use the first window's order from the input array
        var pidOrder: [pid_t] = []
        var seen = Set<pid_t>()
        for w in windows {
            if seen.insert(w.pid).inserted {
                pidOrder.append(w.pid)
            }
        }

        return pidOrder.compactMap { pid -> WindowInfo? in
            guard let appWindows = grouped[pid], let representative = appWindows.first else { return nil }
            let visibleCount = appWindows.filter { !$0.isMinimized }.count
            let minimizedCount = appWindows.filter { $0.isMinimized }.count
            let allMinimized = visibleCount == 0

            return WindowInfo(
                id: representative.id,
                title: representative.title,
                appName: representative.appName,
                appIcon: representative.appIcon,
                pid: representative.pid,
                isMinimized: allMinimized,
                axWindow: representative.axWindow,
                visibleCount: visibleCount,
                minimizedCount: minimizedCount
            )
        }
    }

    // MARK: - Full enumeration (parallel AX)

    static func enumerate() -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let zOrder = zOrderMap()

        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
        }

        let lock = NSLock()
        var allResults: [WindowInfo] = []
        var allMinimized: [WindowInfo] = []

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "enumerate", attributes: .concurrent)

        for app in runningApps {
            group.enter()
            queue.async {
                defer { group.leave() }

                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(axApp, 0.5)
                var windowsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                      let axWindows = windowsRef as? [AXUIElement] else {
                    return
                }

                let name = app.localizedName ?? "Unknown"
                let icon = appIcon(for: app)

                var visible: [WindowInfo] = []
                var minimized: [WindowInfo] = []

                for ax in axWindows {
                    guard let info = readWindowInfo(from: ax, appName: name, appIcon: icon, pid: app.processIdentifier) else { continue }
                    if info.isMinimized {
                        minimized.append(info)
                    } else {
                        visible.append(info)
                    }
                }

                lock.lock()
                allResults.append(contentsOf: visible)
                allMinimized.append(contentsOf: minimized)
                lock.unlock()
            }
        }

        group.wait()

        allResults.sort { (zOrder[$0.id] ?? Int.max) < (zOrder[$1.id] ?? Int.max) }
        allResults.append(contentsOf: allMinimized)
        return allResults
    }

    // MARK: - Single-app enumeration

    static func enumerateForApp(pid: pid_t) -> [WindowInfo] {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) else {
            return []
        }

        let zOrder = zOrderMap()

        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return []
        }

        let name = app.localizedName ?? "Unknown"
        let icon = appIcon(for: app)

        var results: [WindowInfo] = []
        var minimizedResults: [WindowInfo] = []

        for ax in axWindows {
            guard let info = readWindowInfo(from: ax, appName: name, appIcon: icon, pid: pid) else { continue }

            if info.isMinimized {
                minimizedResults.append(info)
            } else if let z = zOrder[info.id] {
                let insertIndex = results.firstIndex(where: { zOrder[$0.id] ?? Int.max > z }) ?? results.endIndex
                results.insert(info, at: insertIndex)
            } else {
                results.append(info)
            }
        }

        results.append(contentsOf: minimizedResults)
        return results
    }
}
