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

    private var wordCount: Int {
        let words = content.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }

    private var lineCount: Int {
        guard !content.isEmpty else { return 0 }
        return content.components(separatedBy: "\n").count
    }

    private var readTime: String {
        let minutes = max(1, wordCount / 200)
        return "\(minutes) min read"
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

                Text("\(wordCount) words")
                Text("\(lineCount) lines")
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
