import SwiftUI

struct StatusBar: View {
    @EnvironmentObject var appState: AppState

    private var currentFile: String? {
        let tab = appState.focusedPane == .secondary
            ? appState.secondaryTab : appState.primaryTab
        return tab?.filePath
    }

    private var content: String {
        guard let path = currentFile else { return "" }
        return appState.contentCache[path] ?? ""
    }

    private var stats: (words: Int, lines: Int) {
        guard !content.isEmpty else { return (0, 0) }
        var words = 0, lines = 1, inWord = false
        for c in content.unicodeScalars {
            if c == "\n" { lines += 1 }
            if c.properties.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
            }
        }
        return (words, lines)
    }

    private var readTime: String {
        "\(max(1, stats.words / 200)) min read"
    }

    private var isDirty: Bool {
        guard let path = currentFile else { return false }
        return appState.dirtyFiles.contains(path)
    }

    var body: some View {
        HStack(spacing: 16) {
            if currentFile != nil {
                // Dirty state
                if isDirty {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                        Text("Modified")
                            .foregroundStyle(.orange)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 9))
                        Text("Saved")
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                Text("\(stats.words) words")
                Text("\(stats.lines) lines")
                Text(readTime)
            } else {
                Spacer()
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 22)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
