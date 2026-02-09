import SwiftUI

struct WindowSwitcherView: View {
    @ObservedObject var state: WindowSwitcherState

    var body: some View {
        VStack(spacing: 8) {
            // Window grid
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(148), spacing: 12), count: max(state.columns, 1)),
                        spacing: 12
                    ) {
                        ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, window in
                            WindowItemView(
                                window: window,
                                isSelected: index == state.selectedIndex
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: state.selectedIndex) { newIndex in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            // Selected window info
            if let selected = state.selectedWindow {
                VStack(spacing: 2) {
                    Text(selected.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(selected.appName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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

            if window.isMinimized {
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
