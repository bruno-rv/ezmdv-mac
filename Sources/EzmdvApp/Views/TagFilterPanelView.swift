import SwiftUI

// MARK: - Tag Filter Panel (collapsible, lives below the file tree)

struct TagFilterPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded: Bool = true

    private var sortedTags: [(tag: String, count: Int)] {
        appState.tagIndex
            .map { (tag: $0.key, count: $0.value.count) }
            .sorted { $0.tag < $1.tag }
    }

    var body: some View {
        if !sortedTags.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(sortedTags, id: \.tag) { item in
                    Button(action: { appState.activeTagFilter = item.tag }) {
                        HStack(spacing: 4) {
                            Text("#\(item.tag)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(
                                    appState.activeTagFilter == item.tag
                                        ? Color.accentColor
                                        : Color.primary
                                )
                            Spacer()
                            Text("\(item.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            } label: {
                Text("Tags")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Tag Filtered Files View (replaces file tree when a tag is active)

struct TagFilteredFilesView: View {
    @EnvironmentObject var appState: AppState
    let tag: String

    private struct TaggedFile: Identifiable {
        let id = UUID()
        let filePath: String
        let fileName: String
        let projectName: String
        let projectId: UUID
    }

    private var matchingFiles: [TaggedFile] {
        guard let paths = appState.tagIndex[tag] else { return [] }
        let uniquePaths = Array(Set(paths)).sorted()
        return uniquePaths.compactMap { path in
            guard let project = appState.projects.first(where: { path.hasPrefix($0.path) })
            else { return nil }
            return TaggedFile(
                filePath: path,
                fileName: (path as NSString).lastPathComponent,
                projectName: project.name,
                projectId: project.id
            )
        }
    }

    var body: some View {
        List(matchingFiles) { file in
            Button(action: {
                appState.openFile(projectId: file.projectId, filePath: file.filePath)
            }) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.fileName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(file.projectName)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
    }
}
