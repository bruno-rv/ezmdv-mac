import SwiftUI

struct MarkdownPaneView: View {
    @EnvironmentObject var appState: AppState
    let pane: AppState.Pane
    let tab: FileTab
    let splitContext: Bool

    @State private var zoom: Double = 1.0
    @State private var tocOpen: Bool = false
    @State private var backlinksOpen: Bool = false
    @State private var editorMode: String = "view"  // "view" | "edit" | "preview"
    @State private var isFullscreen: Bool = false
    @State private var headings: [TOCHeading] = []
    @State private var autoScrollActive: Bool = false
    @State private var autoScrollInterval: Double = 5
    @State private var autoScrollPercent: Double = 10

    var body: some View {
        VStack(spacing: 0) {
            PaneToolbar(
                pane: pane,
                splitContext: splitContext,
                zoom: $zoom,
                tocOpen: $tocOpen,
                backlinksOpen: $backlinksOpen,
                editorMode: $editorMode,
                isFullscreen: $isFullscreen,
                autoScrollActive: $autoScrollActive,
                autoScrollInterval: $autoScrollInterval,
                autoScrollPercent: $autoScrollPercent,
                onRefresh: {
                    appState.refreshContent(for: tab.filePath)
                },
                onSave: {
                    appState.saveFile(tab.filePath)
                },
                onAutoScrollToggle: {
                    autoScrollActive.toggle()
                }
            )

            HStack(spacing: 0) {
                // Main content
                MarkdownWebView(
                    filePath: tab.filePath,
                    zoom: zoom,
                    editorMode: editorMode,
                    autoScrollActive: autoScrollActive,
                    autoScrollInterval: autoScrollInterval,
                    autoScrollPercent: autoScrollPercent,
                    onHeadingsExtracted: { extracted in
                        headings = extracted
                    },
                    onContentChanged: { newContent in
                        appState.contentCache[tab.filePath] = newContent
                        appState.markDirty(tab.filePath)
                    },
                    onAutoScrollStopped: {
                        autoScrollActive = false
                    }
                )
                .id(tab.filePath)
                .onReceive(NotificationCenter.default.publisher(for: .toggleEditMode)) { _ in
                    guard appState.focusedPane == pane else { return }
                    editorMode = editorMode == "edit" ? "view" : "edit"
                    if editorMode == "edit" { autoScrollActive = false }
                }
                .onReceive(NotificationCenter.default.publisher(for: .togglePreviewMode)) { _ in
                    guard appState.focusedPane == pane else { return }
                    editorMode = editorMode == "preview" ? "view" : "preview"
                }
                .onReceive(NotificationCenter.default.publisher(for: .saveCurrentFile)) { _ in
                    guard appState.focusedPane == pane else { return }
                    appState.saveFile(tab.filePath)
                }
                .onReceive(NotificationCenter.default.publisher(for: .exportHTML)) { _ in
                    guard appState.focusedPane == pane else { return }
                    if let content = appState.contentCache[tab.filePath] {
                        ExportService.exportHTML(markdown: content, fileName: tab.fileName)
                    }
                }

                // Side panels (right side)
                if tocOpen && !headings.isEmpty {
                    TOCView(headings: headings) { anchor in
                        NotificationCenter.default.post(
                            name: .scrollToHeading,
                            object: nil,
                            userInfo: ["anchor": anchor, "filePath": tab.filePath]
                        )
                    }
                    .transition(.move(edge: .trailing))
                }

                if backlinksOpen {
                    BacklinksView(filePath: tab.filePath)
                        .transition(.move(edge: .trailing))
                }
            }
        }
    }
}

extension Notification.Name {
    static let scrollToHeading = Notification.Name("scrollToHeading")
}
