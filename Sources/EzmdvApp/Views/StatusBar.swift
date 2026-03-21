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

            aboutButton
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 22)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .onReceive(NotificationCenter.default.publisher(for: .showAbout)) { _ in
            showAbout = true
        }
    }

    @State private var showAbout = false

    private var aboutButton: some View {
        Button(action: { showAbout = true }) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("About ezmdv")
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("ezmdv")
                .font(.title.bold())

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A native macOS markdown viewer & editor")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("by Bruno")
                    .font(.caption)
                Link("brunorv@hotmail.com", destination: URL(string: "mailto:brunorv@hotmail.com")!)
                    .font(.caption)
            }

            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .padding(30)
        .frame(width: 300)
    }
}
