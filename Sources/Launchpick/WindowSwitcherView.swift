import SwiftUI

struct WindowSwitcherView: View {
    @ObservedObject var state: WindowSwitcherState

    var body: some View {
        VStack(spacing: 8) {
            // Window grid
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    let cols = max(state.columns, 1)
                    let items = Array(state.windows.enumerated())
                    let rowCount = items.isEmpty ? 0 : Int(ceil(Double(items.count) / Double(cols)))
                    VStack(spacing: 12) {
                        ForEach(0..<rowCount, id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(0..<cols, id: \.self) { col in
                                    let index = row * cols + col
                                    if index < items.count {
                                        WindowItemView(
                                            window: items[index].element,
                                            isSelected: index == state.selectedIndex
                                        )
                                    } else {
                                        Color.clear.frame(width: 148, height: 148)
                                    }
                                }
                            }
                            .id(row)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: state.selectedIndex) { newIndex in
                    let selectedRow = newIndex / max(state.columns, 1)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(selectedRow, anchor: .center)
                    }
                }
            }

            // Selected window info
            if let selected = state.selectedWindow {
                VStack(spacing: 2) {
                    if state.groupByApp {
                        Text(selected.appName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    } else {
                        Text(selected.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(selected.appName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 12)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WindowItemView: View {
    let window: WindowInfo
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: window.appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)

            if window.visibleCount > 0 || window.minimizedCount > 0 {
                // Grouped mode: show instance counts
                HStack(spacing: 3) {
                    if window.visibleCount > 0 {
                        HStack(spacing: 2) {
                            Text("\(window.visibleCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.85)))
                    }
                    if window.minimizedCount > 0 {
                        HStack(spacing: 2) {
                            Text("\(window.minimizedCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Image(systemName: "minus")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.yellow.opacity(0.85)))
                    }
                }
                .offset(x: 4, y: 4)
            } else if window.isMinimized {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.yellow)
                    .background(Circle().fill(Color.black.opacity(0.5)).frame(width: 18, height: 18))
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 148, height: 148)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
    }
}
