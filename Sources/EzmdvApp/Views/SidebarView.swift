import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onChange(of: searchText) { _, newValue in
                        appState.performSearch(newValue)
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Search results or project tree
            if !searchText.isEmpty {
                SearchResultsView()
            } else {
                ProjectListView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { appState.showOpenFolderDialog() }) {
                    Image(systemName: "plus")
                }
                .help("Open folder (\u{2318}O)")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        DispatchQueue.main.async {
                            appState.addProject(at: url.path)
                        }
                    }
                }
            }
            return true
        }
        // Error alert
        .alert("Error", isPresented: Binding(
            get: { appState.lastError != nil },
            set: { if !$0 { appState.lastError = nil } }
        )) {
            Button("OK") { appState.lastError = nil }
        } message: {
            Text(appState.lastError ?? "")
        }
    }
}

struct SearchResultsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(appState.searchResults) { result in
            Button(action: {
                appState.openFile(projectId: result.projectId, filePath: result.filePath)
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(result.fileName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(result.projectName)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    if let preview = result.preview {
                        Text(preview)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
    }
}

struct ProjectListView: View {
    @EnvironmentObject var appState: AppState
    @State private var renamingProjectId: UUID? = nil
    @State private var renameText: String = ""
    @State private var showDeleteConfirm: Bool = false
    @State private var projectToDelete: Project? = nil
    @State private var deleteFromDisk: Bool = false
    @State private var creatingInProject: UUID? = nil
    @State private var creatingType: FileTreeView.CreationType = .file
    @State private var createText: String = ""

    var body: some View {
        List {
            ForEach(appState.projects) { project in
                projectSection(project)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if appState.projects.isEmpty {
                emptyState
            }
        }
        // Delete project confirmation
        .alert(
            "Delete \"\(projectToDelete?.name ?? "")\"?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Remove from Sidebar") {
                if let proj = projectToDelete {
                    appState.removeProject(proj)
                }
                projectToDelete = nil
            }
            Button("Delete from Disk", role: .destructive) {
                if let proj = projectToDelete {
                    appState.deleteProjectFromDisk(proj)
                }
                projectToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                projectToDelete = nil
            }
        } message: {
            Text("Choose whether to just remove this project from the sidebar, or permanently delete it from disk.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .createFileInFocusedProject)) { _ in
            handleCreateNotification(type: .file)
        }
        .onReceive(NotificationCenter.default.publisher(for: .createFolderInFocusedProject)) { _ in
            handleCreateNotification(type: .folder)
        }
    }

    @ViewBuilder
    private func projectSection(_ project: Project) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { appState.expandedProjectIds.contains(project.id) },
                set: { expanded in
                    if expanded {
                        appState.expandedProjectIds.insert(project.id)
                        if project.files == nil {
                            appState.loadProjectFiles(project)
                        }
                    } else {
                        appState.expandedProjectIds.remove(project.id)
                    }
                }
            )
        ) {
            if let files = project.files {
                FileTreeView(files: files, projectId: project.id)
            }
            // Inline create at project root
            if creatingInProject == project.id {
                HStack(spacing: 5) {
                    Image(systemName: creatingType == .folder ? "folder.badge.plus" : "doc.badge.plus")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    TextField(creatingType == .folder ? "Folder name" : "File name", text: $createText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { submitCreate(project: project) }
                        .onExitCommand { cancelCreate() }
                }
                .padding(.vertical, 2)
            }
        } label: {
            projectLabel(project)
        }
        .contextMenu { projectContextMenu(project) }
    }

    @ViewBuilder
    private func projectLabel(_ project: Project) -> some View {
        if renamingProjectId == project.id {
            TextField("Project name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .onSubmit { submitProjectRename(project) }
                .onExitCommand { cancelProjectRename() }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
                Text(project.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        Button("New File...") {
            creatingInProject = project.id
            creatingType = .file
            createText = ""
            // Ensure project is expanded
            appState.expandedProjectIds.insert(project.id)
            if project.files == nil { appState.loadProjectFiles(project) }
        }

        Button("New Folder...") {
            creatingInProject = project.id
            creatingType = .folder
            createText = ""
            appState.expandedProjectIds.insert(project.id)
            if project.files == nil { appState.loadProjectFiles(project) }
        }

        Divider()

        Button("Rename Project...") {
            renamingProjectId = project.id
            renameText = project.name
        }

        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
        }

        Divider()

        Button("Delete Project...", role: .destructive) {
            projectToDelete = project
            showDeleteConfirm = true
        }
    }

    // MARK: - Actions

    private func submitProjectRename(_ project: Project) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.name else {
            cancelProjectRename()
            return
        }
        appState.renameProject(project, to: trimmed)
        renamingProjectId = nil
    }

    private func cancelProjectRename() {
        renamingProjectId = nil
        renameText = ""
    }

    private func submitCreate(project: Project) {
        let trimmed = createText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            cancelCreate()
            return
        }
        if creatingType == .file {
            appState.createNewFile(in: project, parentPath: project.path, name: trimmed)
        } else {
            appState.createNewFolder(in: project, parentPath: project.path, name: trimmed)
        }
        cancelCreate()
    }

    private func cancelCreate() {
        creatingInProject = nil
        createText = ""
    }

    // Listen for ⌘N / ⌘⇧N from menu bar
    private func handleCreateNotification(type: FileTreeView.CreationType) {
        // Use the first project if available
        guard let project = appState.projects.first else { return }
        creatingInProject = project.id
        creatingType = type
        createText = ""
        appState.expandedProjectIds.insert(project.id)
        if project.files == nil { appState.loadProjectFiles(project) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No projects yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Press \u{2318}O to open a folder")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
