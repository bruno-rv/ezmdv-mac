import SwiftUI

struct BreadcrumbView: View {
    let tab: FileTab
    @EnvironmentObject var appState: AppState

    private var project: Project? {
        appState.projects.first { $0.id == tab.projectId }
    }

    private var segments: [BreadcrumbSegment] {
        guard let proj = project else { return [] }
        let relPath = tab.filePath.replacingOccurrences(of: proj.path + "/", with: "")
        let components = relPath.components(separatedBy: "/")

        var result: [BreadcrumbSegment] = [
            BreadcrumbSegment(name: proj.name, path: proj.path, isFile: false)
        ]
        var currentPath = proj.path
        for (i, component) in components.enumerated() {
            currentPath = (currentPath as NSString).appendingPathComponent(component)
            result.append(BreadcrumbSegment(
                name: component,
                path: currentPath,
                isFile: i == components.count - 1
            ))
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(Array(segments.enumerated()), id: \.offset) { i, segment in
                    if i > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .light))
                            .foregroundStyle(.quaternary)
                    }
                    BreadcrumbSegmentButton(segment: segment, tab: tab)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Segment model

struct BreadcrumbSegment {
    let name: String
    let path: String
    let isFile: Bool
}

// MARK: - Segment button with popover

struct BreadcrumbSegmentButton: View {
    let segment: BreadcrumbSegment
    let tab: FileTab
    @EnvironmentObject var appState: AppState
    @State private var showPopover = false

    private var project: Project? {
        appState.projects.first { $0.id == tab.projectId }
    }

    /// Contents of this directory segment to show in the popover.
    private var contents: [MarkdownFile] {
        guard !segment.isFile,
              let proj = project,
              let files = proj.files else { return [] }
        if segment.path == proj.path {
            return files
        }
        return findChildren(in: files, at: segment.path) ?? []
    }

    var body: some View {
        if segment.isFile {
            Text(segment.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else {
            Button(action: { showPopover = true }) {
                Text(segment.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                contentsPopover
            }
        }
    }

    @ViewBuilder
    private var contentsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(contents) { file in
                    Button(action: {
                        if !file.isDirectory {
                            appState.openFile(projectId: tab.projectId, filePath: file.path)
                        }
                        showPopover = false
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: file.isDirectory ? "folder" : "doc.text")
                                .font(.system(size: 11))
                                .foregroundStyle(file.isDirectory ? .blue : .secondary)
                            Text(file.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .foregroundStyle(file.path == tab.filePath ? Color.accentColor : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(file.path == tab.filePath ? Color.accentColor.opacity(0.1) : Color.clear)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minWidth: 180, maxHeight: 280)
    }

    private func findChildren(in files: [MarkdownFile], at path: String) -> [MarkdownFile]? {
        for file in files {
            if file.isDirectory {
                if file.path == path { return file.children ?? [] }
                if let found = findChildren(in: file.children ?? [], at: path) { return found }
            }
        }
        return nil
    }
}
