import SwiftUI

struct TabBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(appState.tabs) { tab in
                    TabItemView(tab: tab)
                }
                Spacer()
            }
        }
        .frame(height: 32)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct TabItemView: View {
    let tab: FileTab
    @EnvironmentObject var appState: AppState
    @State private var hovering = false

    private var isActive: Bool {
        let active = appState.focusedPane == .secondary
            ? appState.secondaryTab : appState.primaryTab
        return active == tab
    }

    private var isDirty: Bool {
        appState.dirtyFiles.contains(tab.filePath)
    }

    var body: some View {
        Button(action: {
            appState.openFile(projectId: tab.projectId, filePath: tab.filePath)
        }) {
            HStack(spacing: 6) {
                // Dirty indicator (only for unpinned tabs — pinned use pin icon)
                if isDirty && !tab.isPinned {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }

                // Pin icon for pinned tabs
                if tab.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(isDirty ? .orange : Color.accentColor.opacity(0.7))
                }

                Text(tab.fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .primary : .secondary)

                // Close button only for unpinned tabs
                if !tab.isPinned && (hovering || isActive) {
                    Button(action: { appState.closeTab(tab) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            if tab.isPinned {
                Button("Unpin Tab") { appState.setPinned(tab, pinned: false) }
                Divider()
                Button("Close Tab", role: .destructive) { appState.closeTab(tab) }
            } else {
                Button("Pin Tab") { appState.setPinned(tab, pinned: true) }
                Divider()
                Button("Close Tab") { appState.closeTab(tab) }
            }
        }
        .overlay(alignment: .trailing) {
            Divider().frame(height: 16)
        }
    }
}
