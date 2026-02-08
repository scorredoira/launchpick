import Cocoa
import SwiftUI

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let appIcon: NSImage
    let pid: pid_t
    let isMinimized: Bool
    let axWindow: AXUIElement
}

class WindowSwitcherState: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex: Int = 0

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
    static func enumerate() -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Get on-screen windows via CGWindowList for Z-ordering
        guard let cgWindowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        // Build Z-order map: windowID -> z-index (lower = more recent / on top)
        var zOrder: [CGWindowID: Int] = [:]
        for (index, info) in cgWindowList.enumerated() {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            zOrder[windowID] = index
        }

        // Enumerate all windows via Accessibility API
        var results: [WindowInfo] = []
        var minimizedResults: [WindowInfo] = []

        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ownPID else {
                continue
            }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else {
                continue
            }

            let appName = app.localizedName ?? "Unknown"
            let appIcon = app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()

            for axWindow in axWindows {
                // Get window title
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String ?? ""

                // Skip windows with empty titles
                guard !title.isEmpty else { continue }

                // Check if minimized
                var minimizedRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
                let isMinimized = (minimizedRef as? Bool) ?? false

                // Get window ID via private API
                var windowID: CGWindowID = 0
                let axErr = _AXUIElementGetWindow(axWindow, &windowID)

                // If we can't get the window ID, assign a synthetic one
                let finalID: CGWindowID
                if axErr == .success && windowID != 0 {
                    finalID = windowID
                } else {
                    finalID = CGWindowID(arc4random())
                }

                let info = WindowInfo(
                    id: finalID,
                    title: title,
                    appName: appName,
                    appIcon: appIcon,
                    pid: app.processIdentifier,
                    isMinimized: isMinimized,
                    axWindow: axWindow
                )

                if isMinimized {
                    minimizedResults.append(info)
                } else if let z = zOrder[finalID] {
                    // Insert sorted by Z-order
                    let insertIndex = results.firstIndex(where: { zOrder[$0.id] ?? Int.max > z }) ?? results.endIndex
                    results.insert(info, at: insertIndex)
                } else {
                    // On-screen but not in CG list (rare), add at end of visible
                    results.append(info)
                }
            }
        }

        // Minimized windows go at the end
        results.append(contentsOf: minimizedResults)
        return results
    }
}
