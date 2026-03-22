import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCommandPalette = false
    @State private var showGraph = false
    @State private var isGraphMinimized = false
    @State private var showOrphanFinder = false
    @State private var escapeMonitor: Any? = nil
    @State private var isExportingSite = false
    @State private var exportTotalFiles = 0
    @State private var exportCompletedFiles = 0
    @State private var exportCurrentFileName = ""
    @State private var activeExporter: StaticSiteExporter? = nil

    var body: some View {
        NavigationSplitView(columnVisibility: showGraph ? .constant(.detailOnly) : .constant(.doubleColumn)) {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                if !appState.tabs.isEmpty && !appState.isFocusMode && !showGraph {
                    TabBarView()
                }
                if showGraph {
                    if let tab = appState.primaryTab {
                        GraphView(isPresented: $showGraph, projectId: tab.projectId, isMinimized: $isGraphMinimized)
                    }
                } else {
                    DetailContentView()
                }
                if !appState.isFocusMode && !showGraph {
                    StatusBar()
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        .preferredColorScheme(appState.isDarkMode ? .dark : .light)
        .onAppear {
            NSApp.appearance = NSAppearance(named: appState.isDarkMode ? .darkAqua : .aqua)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            showCommandPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKnowledgeGraph)) { _ in
            showGraph.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOrphanFinder)) { _ in
            showOrphanFinder.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportVaultSite)) { _ in
            handleExportVaultSite()
        }
        .sheet(isPresented: $isExportingSite) {
            SiteExportProgressView(
                totalFiles: exportTotalFiles,
                completedFiles: $exportCompletedFiles,
                currentFileName: $exportCurrentFileName,
                onCancel: {
                    activeExporter?.cancel()
                    isExportingSite = false
                }
            )
        }
        .animation(.easeOut(duration: 0.2), value: showGraph)
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }

                    VStack {
                        CommandPalette(isPresented: $showCommandPalette)
                            .padding(.top, 60)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCommandPalette)
        .overlay(alignment: .center) {
            if showOrphanFinder {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { showOrphanFinder = false }
                    OrphanFinderView(isPresented: $showOrphanFinder)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showOrphanFinder)
        .onAppear {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape
                    if showGraph { showGraph = false; return nil }
                    if showOrphanFinder { showOrphanFinder = false; return nil }
                    if appState.isFocusMode { appState.isFocusMode = false; return nil }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
        }
    }

    private func handleExportVaultSite() {
        let targetProject: Project
        if let focusedTab = appState.primaryTab,
           let p = appState.projects.first(where: { $0.id == focusedTab.projectId }) {
            targetProject = p
        } else if let first = appState.projects.first {
            targetProject = first
        } else {
            let alert = NSAlert()
            alert.messageText = "No Project Open"
            alert.informativeText = "Open a folder first, then export it as a site."
            alert.runModal()
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose an output folder for the static site"
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        if targetProject.files == nil { appState.loadProjectFiles(targetProject) }

        let total = MarkdownFile.flatten(targetProject.files)
            .filter { !$0.isDirectory && $0.name.hasSuffix(".md") }.count
        exportTotalFiles = total
        exportCompletedFiles = 0
        exportCurrentFileName = ""

        let exporter = StaticSiteExporter()
        activeExporter = exporter
        isExportingSite = true

        exporter.export(
            project: targetProject,
            outputURL: outputURL,
            onProgress: { completed, fileName in
                exportCompletedFiles = completed
                exportCurrentFileName = fileName
            },
            onComplete: { errorMessage in
                isExportingSite = false
                activeExporter = nil
                if let msg = errorMessage {
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = msg
                    alert.runModal()
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            }
        )
    }
}

struct DetailContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.splitView {
            SplitContentView()
        } else if let tab = appState.primaryTab {
            MarkdownPaneView(pane: .primary, tab: tab, splitContext: false)
        } else {
            EmptyStateView()
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Select a file to view")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            let recents = recentItems()
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("RECENT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 28)
                        .padding(.bottom, 6)

                    ForEach(recents, id: \.path) { item in
                        Button(action: {
                            appState.openFile(projectId: item.projectId, filePath: item.path)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.projectName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 340)
            }

            Button(action: { appState.showOpenFolderDialog() }) {
                Label("Open Folder", systemImage: "folder.badge.plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .padding(.top, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct RecentItem {
        let path: String
        let name: String
        let projectName: String
        let projectId: UUID
    }

    private func recentItems() -> [RecentItem] {
        var results: [RecentItem] = []
        for path in appState.recentFilePaths.prefix(5) {
            guard let (project, file) = findFile(at: path) else { continue }
            results.append(RecentItem(path: path, name: file.name,
                                      projectName: project.name, projectId: project.id))
        }
        return results
    }

    private func findFile(at filePath: String) -> (Project, MarkdownFile)? {
        appState.findFile(at: filePath)
    }
}
