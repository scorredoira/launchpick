import Cocoa

enum IconResolver {
    static func resolve(icon: String?, exec: String) -> NSImage {
        // Explicit icon specified
        if let icon = icon {
            if icon.hasPrefix("sf:") {
                let symbolName = String(icon.dropFirst(3))
                if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                    img.size = NSSize(width: 48, height: 48)
                    return img
                }
            }

            if icon.hasSuffix(".app") {
                return NSWorkspace.shared.icon(forFile: icon)
            }

            if let img = NSImage(contentsOfFile: icon) {
                return img
            }
        }

        // Auto-detect from exec command
        if let appPath = detectAppPath(from: exec) {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        // Default icon
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 48, height: 48))
    }

    private static func detectAppPath(from exec: String) -> String? {
        let patterns = [
            #"open\s+(?:-\w\s+)*-a\s+'([^']+)'"#,
            #"open\s+(?:-\w\s+)*-a\s+"([^"]+)""#,
            #"open\s+(?:-\w\s+)*-a\s+(\S+)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: exec, range: NSRange(exec.startIndex..., in: exec)),
                  let range = Range(match.range(at: 1), in: exec) else { continue }

            let appName = String(exec[range])
            if let path = findAppBundle(named: appName) {
                return path
            }
        }
        return nil
    }

    private static func findAppBundle(named name: String) -> String? {
        if name.contains("/") && FileManager.default.fileExists(atPath: name) {
            return name
        }

        let searchPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            "\(NSHomeDirectory())/Applications",
        ]

        for basePath in searchPaths {
            let appPath = "\(basePath)/\(name).app"
            if FileManager.default.fileExists(atPath: appPath) {
                return appPath
            }
        }

        return nil
    }
}
