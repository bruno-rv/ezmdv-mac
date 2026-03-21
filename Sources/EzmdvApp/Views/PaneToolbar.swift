import SwiftUI

struct PaneToolbar: View {
    @EnvironmentObject var appState: AppState
    let pane: AppState.Pane
    let splitContext: Bool

    @Binding var zoom: Double
    @Binding var tocOpen: Bool
    @Binding var backlinksOpen: Bool
    @Binding var editorMode: String  // "view" | "edit" | "preview"
    @Binding var isFullscreen: Bool
    @Binding var autoScrollActive: Bool
    @Binding var autoScrollInterval: Double
    @Binding var autoScrollPercent: Double
    let onRefresh: () -> Void
    let onSave: () -> Void
    let onAutoScrollToggle: () -> Void

    private var tab: FileTab? {
        pane == .primary ? appState.primaryTab : appState.secondaryTab
    }
    private var isFocused: Bool {
        appState.focusedPane == pane
    }
    private var isDirty: Bool {
        guard let filePath = tab?.filePath else { return false }
        return appState.isFileDirty(filePath)
    }

    var body: some View {
        HStack(spacing: 6) {
            // Left: split label + filename
            if splitContext {
                Text(pane == .primary ? "Left" : "Right")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isFocused ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                    .clipShape(Capsule())
            }

            if let tab = tab {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(tab.fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 3-way mode toggle
            HStack(spacing: 0) {
                modeButton(mode: "view", icon: "eye", label: "View")
                modeButton(mode: "edit", icon: "pencil", label: "Edit")
                if !splitContext {
                    modeButton(mode: "preview", icon: "rectangle.split.2x1", label: "Preview")
                }
            }
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Auto-scroll toggle (only in view or preview modes)
            if editorMode == "view" || editorMode == "preview" {
                AutoScrollButton(
                    active: $autoScrollActive,
                    intervalSeconds: $autoScrollInterval,
                    scrollPercent: $autoScrollPercent,
                    onToggle: onAutoScrollToggle
                )
            }

            // Actions menu
            Menu {
                toolbarMenuContent
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func modeButton(mode: String, icon: String, label: String) -> some View {
        Button(action: { editorMode = mode }) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 28, height: 22)
                .background(editorMode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                .foregroundStyle(editorMode == mode ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    @ViewBuilder
    private var toolbarMenuContent: some View {
        // Panels
        Section("Panels") {
            Button(action: { tocOpen.toggle() }) {
                Label("Table of Contents", systemImage: "list.bullet")
            }
            Button(action: { backlinksOpen.toggle() }) {
                Label("Backlinks", systemImage: "link")
            }
            Button(action: {
                NotificationCenter.default.post(name: .showKnowledgeGraph, object: nil)
            }) {
                Label("Knowledge Graph", systemImage: "chart.dots.scatter")
            }
        }

        // View
        Section("View") {
            Button(action: onRefresh) {
                Label("Refresh from Disk", systemImage: "arrow.clockwise")
            }

            Button(action: { isFullscreen.toggle() }) {
                Label(isFullscreen ? "Exit Fullscreen" : "Fullscreen",
                      systemImage: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }

            if !splitContext {
                Button(action: { appState.toggleSplitView() }) {
                    Label("Split View", systemImage: "rectangle.split.2x1")
                }
            } else {
                Button(action: { appState.toggleSplitView() }) {
                    Label("Close Split", systemImage: "rectangle.split.2x1")
                }
            }
        }

        // Zoom
        Section("Zoom") {
            Button(action: { zoom = min(zoom + 0.1, 2.0) }) {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            Button(action: { zoom = max(zoom - 0.1, 0.5) }) {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            Button(action: { zoom = 1.0 }) {
                Label("Reset Zoom (\(Int(zoom * 100))%)", systemImage: "1.magnifyingglass")
            }
        }

        // Save (edit or preview mode)
        if editorMode != "view" {
            Divider()
            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
        }
    }
}
