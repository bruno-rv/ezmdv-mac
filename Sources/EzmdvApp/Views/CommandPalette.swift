import SwiftUI

struct CommandPalette: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    private var isActionMode: Bool { query.hasPrefix(">") }
    private var searchQuery: String {
        isActionMode ? String(query.dropFirst()).trimmingCharacters(in: .whitespaces) : query
    }

    private var results: [PaletteItem] {
        if isActionMode {
            return filteredActions
        } else {
            return filteredFiles
        }
    }

    private var filteredFiles: [PaletteItem] {
        let q = searchQuery.lowercased()
        var items: [PaletteItem] = []
        var seenPaths = Set<String>()

        // When query is empty, show recent files (not currently open as primary) first
        if q.isEmpty {
            for filePath in appState.recentFilePaths.prefix(6) {
                guard filePath != appState.primaryTab?.filePath else { continue }
                guard let (project, file) = findFile(at: filePath) else { continue }
                items.append(PaletteItem(
                    icon: "clock", title: file.name,
                    subtitle: project.name, kind: .recent,
                    score: 1000,
                    action: { appState.openFile(projectId: project.id, filePath: filePath); isPresented = false }
                ))
                seenPaths.insert(filePath)
            }
        }

        // Open tabs
        for tab in appState.tabs {
            let projectName = appState.projects.first { $0.id == tab.projectId }?.name ?? ""
            let score = fuzzyScore(query: q, target: tab.fileName.lowercased())
            if q.isEmpty || score > 0 {
                if !seenPaths.contains(tab.filePath) {
                    items.append(PaletteItem(
                        icon: "doc.text", title: tab.fileName,
                        subtitle: projectName, kind: .tab,
                        score: score + (tab == appState.primaryTab ? 50 : 0),
                        action: { appState.openFile(projectId: tab.projectId, filePath: tab.filePath); isPresented = false }
                    ))
                    seenPaths.insert(tab.filePath)
                }
            }
        }

        // All project files
        for project in appState.projects {
            guard let files = project.files else { continue }
            for file in flattenFiles(files) {
                if seenPaths.contains(file.path) { continue }
                let score = fuzzyScore(query: q, target: file.name.lowercased())
                let pathScore = fuzzyScore(query: q, target: file.relativePath.lowercased())
                let best = max(score, pathScore)
                if q.isEmpty || best > 0 {
                    items.append(PaletteItem(
                        icon: "doc", title: file.name,
                        subtitle: "\(project.name) · \(file.relativePath)", kind: .file,
                        score: best,
                        action: { appState.openFile(projectId: project.id, filePath: file.path); isPresented = false }
                    ))
                    seenPaths.insert(file.path)
                }
            }
        }

        return items.sorted { $0.score > $1.score }.prefix(12).map { $0 }
    }

    private func findFile(at filePath: String) -> (Project, MarkdownFile)? {
        appState.findFile(at: filePath)
    }

    private var filteredActions: [PaletteItem] {
        let q = searchQuery.lowercased()
        let actions: [PaletteItem] = [
            PaletteItem(icon: "square.and.arrow.down", title: "Save", subtitle: "⌘S", kind: .action, score: 0,
                        action: { NotificationCenter.default.post(name: .saveCurrentFile, object: nil); isPresented = false }),
            PaletteItem(icon: "pencil", title: "Toggle Edit Mode", subtitle: "⌘E", kind: .action, score: 0,
                        action: { NotificationCenter.default.post(name: .toggleEditMode, object: nil); isPresented = false }),
            PaletteItem(icon: "rectangle.split.2x1", title: "Live Preview", subtitle: "⌘⇧P", kind: .action, score: 0,
                        action: { NotificationCenter.default.post(name: .togglePreviewMode, object: nil); isPresented = false }),
            PaletteItem(icon: "rectangle.split.2x1", title: "Toggle Split View", subtitle: "⌘\\", kind: .action, score: 0,
                        action: { appState.toggleSplitView(); isPresented = false }),
            PaletteItem(icon: "moon", title: "Toggle Dark Mode", subtitle: "⌘⇧D", kind: .action, score: 0,
                        action: { appState.toggleTheme(); isPresented = false }),
            PaletteItem(icon: "folder", title: "Open Folder", subtitle: "⌘O", kind: .action, score: 0,
                        action: { appState.showOpenFolderDialog(); isPresented = false }),
        ]
        if q.isEmpty { return actions }
        return actions.filter { fuzzyScore(query: q, target: $0.title.lowercased()) > 0 }
            .map { var item = $0; item.score = fuzzyScore(query: q, target: $0.title.lowercased()); return item }
            .sorted { $0.score > $1.score }
    }

    private func flattenFiles(_ files: [MarkdownFile]) -> [MarkdownFile] {
        MarkdownFile.flatten(files)
    }

    private func fuzzyScore(query: String, target: String) -> Int {
        FuzzyMatcher.score(query: query, target: target)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                TextField(isActionMode ? "Type a command..." : "Search files... (> for commands)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isFocused)
                    .onSubmit { executeSelected() }
                    .onChange(of: query) { _, _ in selectedIndex = 0 }

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Results
            if results.isEmpty {
                Text("No results")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.offset) { idx, item in
                                paletteRow(item: item, isSelected: idx == selectedIndex)
                                    .id(idx)
                                    .onTapGesture { item.action() }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedIndex) { _, newVal in
                        proxy.scrollTo(newVal, anchor: .center)
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .frame(width: 520)
        .onAppear { isFocused = true; query = "" }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.tab) { executeSelected(); return .handled }
        .onKeyPress(.escape) { isPresented = false; return .handled }
    }

    @ViewBuilder
    private func paletteRow(item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundStyle(item.kind == .tab ? Color.accentColor : item.kind == .recent ? Color.secondary : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.kind == .tab {
                Text("Tab")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            } else if item.kind == .recent {
                Text("Recent")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    private func moveSelection(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func executeSelected() {
        guard !results.isEmpty, selectedIndex < results.count else { return }
        results[selectedIndex].action()
    }
}

// MARK: - Palette Item

struct PaletteItem {
    let icon: String
    let title: String
    let subtitle: String
    let kind: PaletteItemKind
    var score: Int
    let action: () -> Void

    enum PaletteItemKind { case tab, file, recent, action }
}
