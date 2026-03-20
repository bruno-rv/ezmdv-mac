import SwiftUI

struct FileTreeView: View {
    let files: [MarkdownFile]
    let projectId: UUID
    @EnvironmentObject var appState: AppState

    @State private var renamingPath: String? = nil
    @State private var renameText: String = ""
    @State private var showDeleteConfirm: Bool = false
    @State private var deletePath: String? = nil
    @State private var creatingIn: String? = nil
    @State private var creatingType: CreationType = .file
    @State private var createText: String = ""

    enum CreationType { case file, folder }

    private var project: Project? {
        appState.projects.first { $0.id == projectId }
    }

    var body: some View {
        Group {
        ForEach(files) { file in
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
            appState.createNewFile(in: proj, parentPath: parentPath, name: trimmed)
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
