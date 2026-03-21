import SwiftUI

struct Backlink: Identifiable {
    let id = UUID()
    let sourceFile: MarkdownFile
    let projectId: UUID
    let linkText: String
    let context: String  // surrounding text
}

struct BacklinksView: View {
    @EnvironmentObject var appState: AppState
    let filePath: String

    private var backlinks: [Backlink] {
        computeBacklinks()
    }

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

            if backlinks.isEmpty {
                VStack(spacing: 6) {
                    Text("No backlinks found")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(backlinks) { bl in
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
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .frame(width: 220)
        .background(.bar)
    }

    private func computeBacklinks() -> [Backlink] {
        var results: [Backlink] = []
        let targetName = (filePath as NSString).lastPathComponent
        let targetBasename = (targetName as NSString).deletingPathExtension.lowercased()

        for project in appState.projects {
            let flat = MarkdownFile.flatten(project.files)
            for file in flat {
                guard file.path != filePath else { continue }
                guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else { continue }

                let nsContent = content as NSString
                let links = WikiLinkResolver.findLinks(in: content)

                for (fullRange, inner) in links {
                    let target = inner.split(separator: "|").first.map(String.init) ?? inner
                    let targetTrimmed = target.trimmingCharacters(in: .whitespaces).lowercased()
                    let targetNoExt = targetTrimmed.hasSuffix(".md")
                        ? String(targetTrimmed.dropLast(3)) : targetTrimmed

                    if targetNoExt == targetBasename || targetTrimmed == targetName.lowercased() {
                        let loc = fullRange.location
                        let ctxStart = max(0, loc - 40)
                        let ctxEnd = min(nsContent.length, loc + fullRange.length + 40)
                        let ctx = nsContent.substring(with: NSRange(location: ctxStart, length: ctxEnd - ctxStart))
                            .replacingOccurrences(of: "\n", with: " ")

                        results.append(Backlink(
                            sourceFile: file, projectId: project.id,
                            linkText: inner, context: "…\(ctx)…"
                        ))
                        break
                    }
                }
            }
        }
        return results
    }
}
