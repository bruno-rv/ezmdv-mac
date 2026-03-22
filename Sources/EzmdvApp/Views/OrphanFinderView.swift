import SwiftUI

struct OrphanFinderView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var selectedIndex: Int = 0

    private var orphans: [(file: MarkdownFile, projectId: UUID)] {
        computeOrphans()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "circle.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("Orphan Notes")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(orphans.count) file\(orphans.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if orphans.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    Text("No orphan notes!")
                        .font(.system(size: 13, weight: .medium))
                    Text("All files are connected via wiki-links.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(orphans.enumerated()), id: \.offset) { idx, item in
                                Button(action: {
                                    appState.openFile(projectId: item.projectId, filePath: item.file.path)
                                    isPresented = false
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.file.name)
                                                .font(.system(size: 12, weight: .medium))
                                            Text(item.file.relativePath)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(idx == selectedIndex
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(idx)
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, newVal in
                        proxy.scrollTo(newVal, anchor: .center)
                    }
                }
            }
        }
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .frame(width: 360)
        .frame(maxHeight: 500)
        .onAppear { selectedIndex = 0 }
        .onKeyPress(.upArrow) {
            let count = orphans.count
            guard count > 0 else { return .ignored }
            selectedIndex = (selectedIndex - 1 + count) % count
            return .handled
        }
        .onKeyPress(.downArrow) {
            let count = orphans.count
            guard count > 0 else { return .ignored }
            selectedIndex = (selectedIndex + 1) % count
            return .handled
        }
        .onKeyPress(.return) {
            guard !orphans.isEmpty, selectedIndex < orphans.count else { return .ignored }
            let item = orphans[selectedIndex]
            appState.openFile(projectId: item.projectId, filePath: item.file.path)
            isPresented = false
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func computeOrphans() -> [(file: MarkdownFile, projectId: UUID)] {
        var results: [(file: MarkdownFile, projectId: UUID)] = []
        for project in appState.projects {
            let flat = MarkdownFile.flatten(project.files)
            for file in flat where !file.isDirectory {
                let baseLower = (file.name as NSString).deletingPathExtension.lowercased()
                let hasIncoming = appState.wikiLinkIndex.hasIncoming(baseLower)
                let hasOutgoing = appState.wikiLinkIndex.hasOutgoing(file.path)
                if !hasIncoming && !hasOutgoing {
                    results.append((file: file, projectId: project.id))
                }
            }
        }
        return results
    }
}

extension Notification.Name {
    static let showOrphanFinder = Notification.Name("showOrphanFinder")
}
