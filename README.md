# Launchpick

Native macOS launcher and window switcher. Free and open source.

![Launchpick](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Why

macOS makes two things surprisingly hard:

**Launching apps with parameters.** On Linux you create a `.desktop` file and you're done. On macOS there's no simple way to have a shortcut that opens, say, VS Code in a specific project folder. Automator is clunky, Shortcuts is limited, and the Dock doesn't support arguments. Paid apps like Alfred or Raycast solve this, but shouldn't need to pay for something this basic.

**Switching between windows, not apps.** Cmd+Tab switches between *applications*. If you have 5 Chrome windows or 3 VS Code projects open, Cmd+Tab just takes you to "Chrome" — you can't pick which window. You can't see individual windows, you can't reach minimized windows, and Cmd+\` only cycles within the *currently focused* app. On Linux and Windows, Alt+Tab shows every window. On macOS, the only free alternative is [AltTab](https://alt-tab-macos.com/).

Launchpick solves both in a single lightweight app.

### Launchpick panel — open apps with custom arguments

One keyboard shortcut opens a Spotlight-like grid where each icon launches a preconfigured command — an app, a URL, a script, or an app with specific arguments like a project folder.

![Launchpick panel](assets/launchpick.png)

### Window switcher — switch between windows, not apps

Option+Tab shows every individual window across all apps — including minimized ones. Pick any VS Code project, any Chrome window, any Terminal session. Release Option to switch to it. Works exactly like Alt+Tab on Linux/Windows.

![Window switcher](assets/switcher.png)

## Download

Download the latest release for your Mac:

- **[Launchpick-AppleSilicon.dmg](https://github.com/scorredoira/launchpick/releases/latest)** — for Apple Silicon Macs (M1, M2, M3, M4)
- **[Launchpick-Intel.dmg](https://github.com/scorredoira/launchpick/releases/latest)** — for Intel Macs

Open the DMG and drag `Launchpick.app` to `/Applications`.

## Features

- **Global hotkey** (Cmd+Shift+Space) to toggle the launcher panel
- **Window switcher** (Option+Tab) — switch between individual windows
- **Interactive shortcut recorder** — click and press keys to set shortcuts
- **Icon grid** with search/filter bar
- **Menu bar icon** with quick access to settings
- **Tabbed settings UI** with General and Launchers tabs
- **Icon picker** with app icons, SF Symbols, and custom images
- **Auto-detect icons** from `open -a` commands
- **Launch at Login** toggle
- **JSON config** at `~/.config/launchpick/config.json`

## Launcher types

- **Open App**: launch any application, optionally with arguments (e.g., open VS Code with a specific project folder)
- **Open URL**: open any URL in the default browser
- **Shell Command**: run any shell command (supports full shell syntax: pipes, `;`, `&&`, redirects, etc.)
- **Kill & Restart**: use shell syntax to restart a process, e.g. `killall handy 2>/dev/null; handy`

## Permissions

### Accessibility (required for Window Switcher)

On first launch, macOS will show a dialog asking for Accessibility permission. This is needed for the Option+Tab window switcher to intercept keyboard events.

1. Click "Open System Settings" in the dialog
2. Toggle **Launchpick** ON in Privacy & Security > Accessibility

If you miss the dialog, go to **System Settings > Privacy & Security > Accessibility**, click **+**, press **Cmd+Shift+G**, type `/Applications/Launchpick.app`, and add it.

The app will automatically detect when permission is granted — no restart needed.

## Build from source

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
bash build.sh
```

This builds the app and creates `build/Launchpick.app`.

### Install from build

```bash
cp -r build/Launchpick.app /Applications/
open /Applications/Launchpick.app
```

## Config

The config file is created automatically on first launch at `~/.config/launchpick/config.json`. Example:

```json
{
  "shortcut": "cmd+shift+space",
  "columns": 4,
  "launchers": [
    {
      "name": "Terminal",
      "exec": "open -a 'Terminal'"
    },
    {
      "name": "My Project",
      "exec": "open -a 'Visual Studio Code' '/path/to/project'",
      "icon": "/Applications/Visual Studio Code.app"
    },
    {
      "name": "GitHub",
      "exec": "open 'https://github.com'",
      "icon": "sf:globe"
    },
    {
      "name": "Restart Handy",
      "exec": "killall handy 2>/dev/null; handy",
      "icon": "sf:arrow.clockwise"
    }
  ]
}
```

### Icon options

- **Auto-detect** (default): resolves the icon from the `open -a` command
- **App icon**: path to a `.app` bundle (e.g., `/Applications/Safari.app`)
- **SF Symbol**: prefix with `sf:` (e.g., `sf:globe`, `sf:terminal.fill`)
- **Custom image**: path to any image file
