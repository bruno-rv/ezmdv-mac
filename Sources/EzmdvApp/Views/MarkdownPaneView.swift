import SwiftUI
import AppKit

private final class FindDebouncer: ObservableObject {
    var workItem: DispatchWorkItem?
    func schedule(delay: Double = 0.3, action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

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
    @State private var printTrigger: Int = 0
    @State private var presentationTrigger: Int = 0
    @State private var enteredFullscreenForPresentation: Bool = false
    @StateObject private var findDebouncer = FindDebouncer()
    @State private var findBarID: UUID = UUID()
    @State private var findBarVisible: Bool = false
    @State private var showReplace: Bool = false
    @State private var findQuery: String = ""
    @State private var replaceText: String = ""
    @State private var findMatchCurrent: Int = 0
    @State private var findMatchTotal: Int = -1
    @State private var findTrigger: Int = 0
    @State private var findDirection: Int = 1
    @State private var replaceTrigger: Int = 0
    @State private var replaceAllTrigger: Int = 0

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
                onSave: {
                    appState.saveFile(tab.filePath)
                },
                onAutoScrollToggle: {
                    autoScrollActive.toggle()
                }
            )

            if !appState.isFocusMode {
                BreadcrumbView(tab: tab)
            }

            HStack(spacing: 0) {
                // Main content
                MarkdownWebView(
                    filePath: tab.filePath,
                    zoom: zoom,
                    editorMode: editorMode,
                    autoScrollActive: autoScrollActive,
                    autoScrollInterval: autoScrollInterval,
                    autoScrollPercent: autoScrollPercent,
                    printTrigger: printTrigger,
                    presentationTrigger: presentationTrigger,
                    findQuery: findQuery,
                    findTrigger: findTrigger,
                    findDirection: findDirection,
                    replaceTrigger: replaceTrigger,
                    replaceAllTrigger: replaceAllTrigger,
                    replaceText: replaceText,
                    findBarVisible: findBarVisible,
                    onHeadingsExtracted: { extracted in
                        headings = extracted
                    },
                    onContentChanged: { newContent in
                        appState.contentCache.set(tab.filePath, newContent)
                        appState.markDirty(tab.filePath)
                    },
                    onAutoScrollStopped: {
                        autoScrollActive = false
                    },
                    onPresentationChanged: { active in
                        handlePresentationChange(active)
                    },
                    onFindResult: { current, total in
                        findMatchCurrent = current
                        findMatchTotal = total
                    },
                    onFindClose: {
                        closeFindBar()
                    }
                )
                .id(tab.filePath)
                .onReceive(NotificationCenter.default.publisher(for: .toggleEditMode)) { _ in
                    guard appState.focusedPane == pane else { return }
                    editorMode = editorMode == "edit" ? "view" : "edit"
                    if editorMode == "edit" { autoScrollActive = false }
                    if editorMode != "edit" { showReplace = false }
                    if findBarVisible {
                        findMatchCurrent = 0
                        findMatchTotal = -1
                        findTrigger += 1
                    }
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
                .onReceive(NotificationCenter.default.publisher(for: .printCurrentFile)) { _ in
                    guard appState.focusedPane == pane else { return }
                    printTrigger += 1
                }
                .onReceive(NotificationCenter.default.publisher(for: .showPresentation)) { _ in
                    guard appState.focusedPane == pane else { return }
                    presentationTrigger += 1
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleFocusMode)) { _ in
                    appState.isFocusMode.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openFind)) { _ in
                    guard appState.focusedPane == pane else { return }
                    showReplace = false
                    openFindBar()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openFindReplace)) { _ in
                    guard appState.focusedPane == pane else { return }
                    showReplace = true
                    openFindBar()
                }
                .onReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in
                    guard appState.focusedPane == pane else { return }
                    guard findBarVisible else { openFindBar(); return }
                    findDirection = 1
                    findTrigger += 1
                }
                .onReceive(NotificationCenter.default.publisher(for: .findPrevious)) { _ in
                    guard appState.focusedPane == pane else { return }
                    guard findBarVisible else { openFindBar(); return }
                    findDirection = -1
                    findTrigger += 1
                }
                .onReceive(NotificationCenter.default.publisher(for: .closeFind)) { _ in
                    guard appState.focusedPane == pane else { return }
                    closeFindBar()
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
            .animation(.spring(duration: 0.25), value: tocOpen)
            .animation(.spring(duration: 0.25), value: backlinksOpen)

            if findBarVisible {
                FindBar(
                    query: $findQuery,
                    replaceText: $replaceText,
                    showReplace: $showReplace,
                    editorMode: editorMode,
                    matchCurrent: findMatchCurrent,
                    matchTotal: findMatchTotal,
                    onFindNext: {
                        findDirection = 1
                        findTrigger += 1
                    },
                    onFindPrev: {
                        findDirection = -1
                        findTrigger += 1
                    },
                    onQueryChanged: { newQuery in
                        findMatchCurrent = 0
                        findMatchTotal = -1
                        if newQuery.isEmpty {
                            findTrigger += 1  // fires findInView("", ...) which clears highlights
                        } else {
                            findDebouncer.schedule {
                                findDirection = 1
                                findTrigger += 1
                            }
                        }
                    },
                    onReplace: { replaceTrigger += 1 },
                    onReplaceAll: { replaceAllTrigger += 1 },
                    onClose: { closeFindBar() }
                )
                .id(findBarID)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: findBarVisible)
    }

    private func openFindBar() {
        findBarID = UUID()
        findBarVisible = true
        findMatchCurrent = 0
        findMatchTotal = -1
        if !findQuery.isEmpty { findTrigger += 1 }
    }

    private func closeFindBar() {
        withAnimation(.easeOut(duration: 0.15)) {
            findBarVisible = false
        }
        findQuery = ""
        replaceText = ""
        findMatchCurrent = 0
        findMatchTotal = -1
    }

    private func handlePresentationChange(_ active: Bool) {
        guard let window = NSApp.keyWindow else { return }
        if active {
            let isAlreadyFullscreen = window.styleMask.contains(.fullScreen)
            enteredFullscreenForPresentation = !isAlreadyFullscreen
            if !isAlreadyFullscreen {
                window.toggleFullScreen(nil)
            }
        } else {
            if enteredFullscreenForPresentation {
                enteredFullscreenForPresentation = false
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let scrollToHeading = Notification.Name("scrollToHeading")
    static let printCurrentFile = Notification.Name("printCurrentFile")
    static let showPresentation = Notification.Name("showPresentation")
    static let toggleFocusMode  = Notification.Name("toggleFocusMode")
}
