import SwiftUI

struct Backlink: Identifiable {
    let id = UUID()
    let sourceFile: MarkdownFile
    let projectId: UUID
    let linkText: String
    let context: String  // surrounding text
}

struct UnlinkedMention: Identifiable {
    let id = UUID()
    let sourceFile: MarkdownFile
    let projectId: UUID
    let context: String
    let matchRange: NSRange  // range in source file content to convert to wiki-link
}

struct BacklinksView: View {
    @EnvironmentObject var appState: AppState
    let filePath: String

    @State private var selectedIndex: Int = 0

    private var backlinks: [Backlink] { computeBacklinks() }
    private var unlinkedMentions: [UnlinkedMention] { computeUnlinkedMentions() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "link")
                    .font(.system(size: 11))
                Text("Backlinks")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(backlinks.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // — Linked backlinks —
                        if backlinks.isEmpty {
                            Text("No backlinks found")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(Array(backlinks.enumerated()), id: \.offset) { idx, bl in
                                Button(action: {
                                    appState.openFile(projectId: bl.projectId, filePath: bl.sourceFile.path)
                                }) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.text")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                            Text(bl.sourceFile.name)
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(1)
                                        }
                                        Text(bl.context)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(idx == selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(idx)
                                Divider().padding(.leading, 12)
                            }
                        }

                        // — Unlinked mentions —
                        if !unlinkedMentions.isEmpty {
                            HStack {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.system(size: 10))
                                Text("Unlinked Mentions")
                                    .font(.system(size: 10, weight: .semibold))
                                Spacer()
                                Text("\(unlinkedMentions.count)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.06))

                            ForEach(unlinkedMentions) { mention in
                                HStack(alignment: .top, spacing: 0) {
                                    Button(action: {
                                        appState.openFile(projectId: mention.projectId,
                                                         filePath: mention.sourceFile.path)
                                    }) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "doc.text")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                                Text(mention.sourceFile.name)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .lineLimit(1)
                                            }
                                            Text(mention.context)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button("Link") {
                                        linkMention(mention)
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.borderless)
                                    .padding(.trailing, 8)
                                    .padding(.top, 8)
                                }
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, newVal in
                    withAnimation { proxy.scrollTo(newVal, anchor: .center) }
                }
            }
        }
        .frame(width: 220)
        .background(.bar)
        .onAppear { selectedIndex = 0 }
        .onKeyPress(.upArrow) {
            guard !backlinks.isEmpty else { return .ignored }
            selectedIndex = (selectedIndex - 1 + backlinks.count) % backlinks.count
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !backlinks.isEmpty else { return .ignored }
            selectedIndex = (selectedIndex + 1) % backlinks.count
            return .handled
        }
        .onKeyPress(.return) {
            guard !backlinks.isEmpty, selectedIndex < backlinks.count else { return .ignored }
            let bl = backlinks[selectedIndex]
            appState.openFile(projectId: bl.projectId, filePath: bl.sourceFile.path)
            return .handled
        }
    }

    // MARK: - Index-backed backlink lookup

    private func computeBacklinks() -> [Backlink] {
        let targetName = ((filePath as NSString).lastPathComponent as NSString)
            .deletingPathExtension.lowercased()
        let entries = appState.wikiLinkIndex.backlinks(for: targetName)
        return entries.compactMap { entry in
            guard let (file, projectId) = findFile(path: entry.sourcePath) else { return nil }
            return Backlink(sourceFile: file, projectId: projectId,
                           linkText: entry.linkText, context: entry.context)
        }
    }

    private func findFile(path: String) -> (MarkdownFile, UUID)? {
        guard let (project, file) = appState.findFile(at: path) else { return nil }
        return (file, project.id)
    }

    // MARK: - Unlinked mentions (uses content cache to avoid disk reads)

    private func computeUnlinkedMentions() -> [UnlinkedMention] {
        var results: [UnlinkedMention] = []
        let targetName = (filePath as NSString).lastPathComponent
        let basename = (targetName as NSString).deletingPathExtension

        guard !basename.isEmpty,
              let mentionRegex = try? NSRegularExpression(
                pattern: "(?<!\\[\\[)\\b\(NSRegularExpression.escapedPattern(for: basename))\\b(?!\\]\\])",
                options: .caseInsensitive)
        else { return [] }

        let wikiPattern = WikiLinkResolver.pattern
        let wikiRegex = try? NSRegularExpression(pattern: wikiPattern)

        // Files already linking to this target (skip them — they're in backlinks, not unlinked)
        let targetLower = basename.lowercased()
        let linkedPaths = Set(appState.wikiLinkIndex.backlinks(for: targetLower).map { $0.sourcePath })

        for project in appState.projects {
            let flat = MarkdownFile.flatten(project.files)
            for file in flat {
                guard file.path != filePath, !file.isDirectory else { continue }
                guard !linkedPaths.contains(file.path) else { continue }
                guard let content = appState.getContent(for: file.path) else { continue }
                let nsContent = content as NSString
                let fullRange = NSRange(location: 0, length: nsContent.length)

                let wikiRanges = (wikiRegex?.matches(in: content, range: fullRange) ?? []).map { $0.range }

                let matches = mentionRegex.matches(in: content, range: fullRange)
                for match in matches {
                    let range = match.range
                    let insideWiki = wikiRanges.contains { NSIntersectionRange($0, range).length > 0 }
                    if insideWiki { continue }

                    let ctxStart = max(0, range.location - 30)
                    let ctxEnd = min(nsContent.length, range.location + range.length + 30)
                    let ctx = nsContent.substring(with: NSRange(location: ctxStart, length: ctxEnd - ctxStart))
                        .replacingOccurrences(of: "\n", with: " ")

                    results.append(UnlinkedMention(
                        sourceFile: file, projectId: project.id,
                        context: "…\(ctx)…", matchRange: range
                    ))
                    break  // one mention per file
                }
            }
        }
        return results
    }

    // MARK: - Link action

    private func linkMention(_ mention: UnlinkedMention) {
        guard let content = appState.getContent(for: mention.sourceFile.path) else { return }
        let nsContent = content as NSString
        let targetName = ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension
        let linked = nsContent.replacingCharacters(in: mention.matchRange, with: "[[\(targetName)]]")
        try? linked.write(toFile: mention.sourceFile.path, atomically: true, encoding: .utf8)
        appState.contentCache.set(mention.sourceFile.path, linked)
        appState.rebuildWikiLinkIndex()
    }
}
