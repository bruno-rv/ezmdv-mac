import SwiftUI

struct FileTreeView: View {
    let files: [MarkdownFile]
    let projectId: UUID
    @EnvironmentObject var appState: AppState

    @State private var renamingPath: String? = nil
    @State private var renameText: String = ""
    @State private var movingFilePath: String? = nil
    @State private var showMoveSheet: Bool = false
    @State private var dropTargetedFolder: String? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var deletePath: String? = nil
    @State private var creatingIn: String? = nil
    @State private var creatingType: CreationType = .file
    @State private var createText: String = ""
    @State private var templateContext: TemplatePickerContext? = nil

    enum CreationType { case file, folder }

    struct TemplatePickerContext: Identifiable {
        let id = UUID()
        let project: Project
        let parentPath: String
        let fileName: String
        let templates: [URL]
    }

    private var project: Project? {
        appState.projects.first { $0.id == projectId }
    }

    private func computeSortedFiles(_ files: [MarkdownFile], order: AppState.FileSortOrder?) -> [MarkdownFile] {
        guard let order else { return files }
        switch order {
        case .nameAsc:
            return files.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .nameDesc:
            return files.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            }
        case .dateModified:
            // Fetch attributes once per file (O(n)) then sort on cached values
            let dates: [String: Date] = Dictionary(uniqueKeysWithValues: files.map { file in
                let date = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date ?? .distantPast
                return (file.path, date)
            })
            return files.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return (dates[lhs.path] ?? .distantPast) > (dates[rhs.path] ?? .distantPast)
            }
        case .size:
            // Fetch attributes once per file (O(n)) then sort on cached values
            let sizes: [String: Int] = Dictionary(uniqueKeysWithValues: files.map { file in
                let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int ?? 0
                return (file.path, size)
            })
            return files.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return (sizes[lhs.path] ?? 0) > (sizes[rhs.path] ?? 0)
            }
        }
    }

    private var sortedFiles: [MarkdownFile] {
        computeSortedFiles(files, order: appState.projectSortOrders[projectId])
    }

    var body: some View {
        Group {
        ForEach(sortedFiles) { file in
            if file.isDirectory {
                directoryRow(file)
            } else {
                fileRow(file)
            }
        }
        // Inline create field
        if let parentPath = creatingIn {
            HStack(spacing: 5) {
                Image(systemName: creatingType == .folder ? "folder.badge.plus" : "doc.badge.plus")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField(creatingType == .folder ? "Folder name" : "File name", text: $createText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { submitCreate(parentPath: parentPath) }
                    .onExitCommand { cancelCreate() }
            }
            .padding(.vertical, 2)
            .padding(.leading, 4)
        }
        } // end Group
        .sheet(item: $templateContext) { ctx in
            TemplatePickerSheet(context: ctx) { templateURL in
                let content: String
                let title = (ctx.fileName as NSString).deletingPathExtension
                if let url = templateURL {
                    content = TemplateService.apply(templateURL: url, title: title)
                } else {
                    content = "# \(title)\n\n"
                }
                appState.createNewFile(in: ctx.project, parentPath: ctx.parentPath,
                                       name: ctx.fileName, content: content)
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            if let sourcePath = movingFilePath, let proj = project {
                FolderPickerSheet(
                    project: proj,
                    sourcePath: sourcePath,
                    onPick: { destFolder in
                        appState.moveFileOrFolder(in: proj, fromPath: sourcePath, toFolderPath: destFolder)
                        showMoveSheet = false
                        movingFilePath = nil
                    },
                    onCancel: {
                        showMoveSheet = false
                        movingFilePath = nil
                    }
                )
            }
        }
        .alert("Delete \"\(deleteItemName)\"?",
               isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let path = deletePath, let proj = project {
                    appState.deleteFileOrFolder(in: proj, path: path)
                }
                deletePath = nil
            }
            Button("Cancel", role: .cancel) { deletePath = nil }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var deleteItemName: String {
        guard let path = deletePath else { return "" }
        return (path as NSString).lastPathComponent
    }

    // MARK: - Directory row

    @ViewBuilder
    private func directoryRow(_ file: MarkdownFile) -> some View {
        DisclosureGroup {
            if let children = file.children {
                FileTreeView(files: children, projectId: projectId)
            }
        } label: {
            if renamingPath == file.path {
                renameField(file)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    Text(file.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
        }
        .contextMenu { folderContextMenu(file) }
    }

    // MARK: - File row

    @ViewBuilder
    private func fileRow(_ file: MarkdownFile) -> some View {
        if renamingPath == file.path {
            HStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                renameField(file)
            }
            .padding(.vertical, 1)
        } else {
            Button(action: {
                appState.openFile(projectId: projectId, filePath: file.path)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    Text(file.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isActiveFile(file) ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contextMenu { fileContextMenu(file) }
        }
    }

    // MARK: - Inline rename field

    @ViewBuilder
    private func renameField(_ file: MarkdownFile) -> some View {
        TextField("Name", text: $renameText)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .onSubmit { submitRename(file) }
            .onExitCommand { cancelRename() }
            .onAppear {
                // Auto-select the name without extension for files
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.keyWindow?.makeFirstResponder(
                        NSApp.keyWindow?.firstResponder
                    )
                }
            }
    }

    // MARK: - Context menus

    @ViewBuilder
    private func fileContextMenu(_ file: MarkdownFile) -> some View {
        Button("Rename...") {
            renamingPath = file.path
            renameText = file.name
        }

        Button("Move to...") {
            movingFilePath = file.path
            showMoveSheet = true
        }

        if appState.splitView {
            Button("Open in Other Pane") {
                let targetPane: AppState.Pane = appState.focusedPane == .primary ? .secondary : .primary
                appState.focusedPane = targetPane
                appState.openFile(projectId: projectId, filePath: file.path)
            }
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: file.path)]
            )
        }

        Divider()

        Button("Delete", role: .destructive) {
            deletePath = file.path
            showDeleteConfirm = true
        }
    }

    @ViewBuilder
    private func folderContextMenu(_ file: MarkdownFile) -> some View {
        Button("New File Here...") {
            creatingIn = file.path
            creatingType = .file
            createText = ""
        }

        Button("New Folder Here...") {
            creatingIn = file.path
            creatingType = .folder
            createText = ""
        }

        Divider()

        Button("Rename...") {
            renamingPath = file.path
            renameText = file.name
        }

        Button("Move to...") {
            movingFilePath = file.path
            showMoveSheet = true
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: file.path)]
            )
        }

        Divider()

        Button("Delete", role: .destructive) {
            deletePath = file.path
            showDeleteConfirm = true
        }
    }

    // MARK: - Actions

    private func submitRename(_ file: MarkdownFile) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != file.name, let proj = project else {
            cancelRename()
            return
        }
        appState.renameFileOrFolder(in: proj, oldPath: file.path, newName: trimmed)
        renamingPath = nil
    }

    private func cancelRename() {
        renamingPath = nil
        renameText = ""
    }

    private func submitCreate(parentPath: String) {
        let trimmed = createText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let proj = project else {
            cancelCreate()
            return
        }
        if creatingType == .file {
            let templates = TemplateService.listTemplates(in: proj)
            if templates.isEmpty {
                appState.createNewFile(in: proj, parentPath: parentPath, name: trimmed)
            } else {
                templateContext = TemplatePickerContext(
                    project: proj, parentPath: parentPath,
                    fileName: trimmed.hasSuffix(".md") ? trimmed : "\(trimmed).md",
                    templates: templates
                )
            }
        } else {
            appState.createNewFolder(in: proj, parentPath: parentPath, name: trimmed)
        }
        cancelCreate()
    }

    private func cancelCreate() {
        creatingIn = nil
        createText = ""
    }

    private func isActiveFile(_ file: MarkdownFile) -> Bool {
        let active = appState.focusedPane == .secondary ? appState.secondaryTab : appState.primaryTab
        return active?.filePath == file.path
    }
}

// MARK: - Template Picker Sheet

struct TemplatePickerSheet: View {
    let context: FileTreeView.TemplatePickerContext
    let onPick: (URL?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Choose a Template")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            Text("Creating: \(context.fileName)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            List {
                Button(action: { onPick(nil); dismiss() }) {
                    Label("Blank file", systemImage: "doc")
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)

                ForEach(context.templates, id: \.absoluteString) { url in
                    Button(action: { onPick(url); dismiss() }) {
                        Label(url.deletingPathExtension().lastPathComponent,
                              systemImage: "doc.text")
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 300, height: 280)
    }
}

// MARK: - Folder Picker Sheet

private struct FolderPickerSheet: View {
    let project: Project
    let sourcePath: String
    let onPick: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Move to Folder")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            let folders = Self.allFolders(from: project.files, root: project.path)
            List(folders, id: \.self) { folder in
                Button(action: { onPick(folder) }) {
                    Label(
                        folder == project.path
                            ? project.name
                            : String(folder.dropFirst(project.path.count + 1)),
                        systemImage: folder == project.path ? "house" : "folder"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(folder == (sourcePath as NSString).deletingLastPathComponent)
            }
        }
        .frame(minWidth: 320, minHeight: 300)
    }

    private static func allFolders(from files: [MarkdownFile]?, root: String) -> [String] {
        var folders = [root]
        func walk(_ items: [MarkdownFile]?) {
            for item in (items ?? []) where item.isDirectory {
                folders.append(item.path)
                walk(item.children)
            }
        }
        walk(files)
        return folders
    }
}
