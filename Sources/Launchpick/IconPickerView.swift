import SwiftUI
import UniformTypeIdentifiers

struct IconPickerView: View {
    @Binding var launcher: EditableLauncher
    @Binding var isPresented: Bool
    @State private var selectedTab = 0
    @State private var symbolSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Apps").tag(0)
                Text("Symbols").tag(1)
                Text("File").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            // Auto-detect option
            Button(action: {
                launcher.iconMode = .auto
                launcher.iconValue = ""
                isPresented = false
            }) {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .frame(width: 20)
                    Text("Auto-detect from command")
                    Spacer()
                    if launcher.iconMode == .auto {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Group {
                switch selectedTab {
                case 0: appIconGrid
                case 1: sfSymbolGrid
                case 2: customFileView
                default: EmptyView()
                }
            }
        }
        .frame(width: 380, height: 440)
    }

    // MARK: - Apps Tab

    var appIconGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 5), spacing: 8) {
                ForEach(AppScanner.shared.apps) { app in
                    Button(action: {
                        launcher.iconMode = .appIcon
                        launcher.iconValue = app.path
                        isPresented = false
                    }) {
                        VStack(spacing: 2) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 36, height: 36)
                            Text(app.name)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .frame(width: 56)
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(launcher.iconMode == .appIcon && launcher.iconValue == app.path
                                      ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Symbols Tab

    var filteredSymbols: [String] {
        if symbolSearch.isEmpty { return SFSymbols.all }
        return SFSymbols.all.filter { $0.localizedCaseInsensitiveContains(symbolSearch) }
    }

    var sfSymbolGrid: some View {
        VStack(spacing: 8) {
            TextField("Search symbols...", text: $symbolSearch)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ScrollView {
                if filteredSymbols.isEmpty {
                    Text("No matching symbols")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 7), spacing: 6) {
                        ForEach(filteredSymbols, id: \.self) { symbol in
                            Button(action: {
                                launcher.iconMode = .sfSymbol
                                launcher.iconValue = symbol
                                isPresented = false
                            }) {
                                Image(systemName: symbol)
                                    .font(.system(size: 18))
                                    .frame(width: 38, height: 38)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(launcher.iconMode == .sfSymbol && launcher.iconValue == symbol
                                                  ? Color.accentColor.opacity(0.2) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(symbol)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Custom File Tab

    var customFileView: some View {
        VStack(spacing: 16) {
            Spacer()

            if launcher.iconMode == .custom, let img = NSImage(contentsOfFile: launcher.iconValue) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .cornerRadius(12)

                Text(URL(fileURLWithPath: launcher.iconValue).lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.5))
            }

            Button("Choose Image...") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.message = "Select an icon image"
                if panel.runModal() == .OK, let url = panel.url {
                    launcher.iconMode = .custom
                    launcher.iconValue = url.path
                    isPresented = false
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SF Symbols Library

enum SFSymbols {
    static let all: [String] = [
        // General
        "star.fill", "heart.fill", "house.fill", "gear", "gearshape.fill",
        "bell.fill", "bookmark.fill", "tag.fill", "flag.fill", "pin.fill",
        "bolt.fill", "eye.fill", "lock.fill", "lock.open.fill", "key.fill",
        "shield.fill", "crown.fill",

        // Media
        "play.fill", "pause.fill", "stop.fill", "forward.fill", "backward.fill",
        "speaker.wave.2.fill", "mic.fill", "music.note", "music.note.list",
        "film", "camera.fill", "video.fill", "photo.fill",

        // Communication
        "envelope.fill", "phone.fill", "message.fill", "bubble.left.fill",
        "bubble.left.and.bubble.right.fill", "paperplane.fill", "at", "link",

        // Editing & Documents
        "pencil", "pencil.circle.fill", "scissors", "paintbrush.fill",
        "doc.fill", "doc.text.fill", "folder.fill", "folder.badge.plus",
        "tray.fill", "tray.2.fill", "archivebox.fill",
        "list.bullet", "list.number", "chart.bar.fill", "chart.pie.fill",

        // Arrows
        "arrow.clockwise", "arrow.counterclockwise",
        "arrow.up.circle.fill", "arrow.down.circle.fill",
        "arrow.left.circle.fill", "arrow.right.circle.fill",
        "arrow.triangle.2.circlepath", "arrowshape.turn.up.right.fill",

        // Devices
        "desktopcomputer", "laptopcomputer", "display",
        "keyboard", "printer.fill", "network", "wifi",
        "antenna.radiowaves.left.and.right", "server.rack",
        "externaldrive.fill", "cpu.fill", "memorychip.fill",

        // Objects
        "briefcase.fill", "cart.fill", "creditcard.fill", "bag.fill",
        "gift.fill", "wrench.fill", "hammer.fill", "screwdriver.fill",

        // Code & Developer
        "terminal.fill", "chevron.left.forwardslash.chevron.right",
        "curlybraces", "number", "textformat",

        // Nature
        "cloud.fill", "cloud.rain.fill", "sun.max.fill", "moon.fill",
        "snowflake", "flame.fill", "drop.fill", "leaf.fill",

        // Shapes
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill",
        "hexagon.fill", "app.fill", "cube.fill", "cylinder.fill",
        "square.grid.2x2.fill",

        // People
        "person.fill", "person.2.fill", "person.3.fill",
        "figure.walk", "hand.raised.fill", "hand.thumbsup.fill",

        // Symbols
        "checkmark.circle.fill", "xmark.circle.fill",
        "plus.circle.fill", "minus.circle.fill",
        "questionmark.circle.fill", "exclamationmark.circle.fill",
        "info.circle.fill",

        // Other
        "globe", "globe.americas.fill", "map.fill", "location.fill",
        "clock.fill", "calendar", "alarm.fill", "timer",
        "battery.100", "power",
        "trash.fill", "magnifyingglass",
        "paintpalette.fill", "gamecontroller.fill",
        "headphones", "airplane",
        "car.fill", "bus.fill", "bicycle",
        "dollarsign.circle.fill", "eurosign.circle.fill",
        "building.fill", "building.2.fill",
        "book.fill", "books.vertical.fill",
        "newspaper.fill", "graduationcap.fill",
        "lightbulb.fill",
        "puzzlepiece.fill", "ticket.fill",
        "wand.and.stars", "sparkles",
    ]
}
