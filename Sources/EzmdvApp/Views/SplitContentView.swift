import SwiftUI

struct SplitContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HSplitView {
            // Primary pane
            paneView(tab: appState.primaryTab, pane: .primary, label: "Left")
                .frame(minWidth: 300)

            // Secondary pane
            paneView(tab: appState.secondaryTab, pane: .secondary, label: "Right")
                .frame(minWidth: 300)
        }
        .overlay(alignment: .top) {
            if appState.primaryTab != nil && appState.secondaryTab != nil {
                Button(action: { appState.swapPanes() }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11))
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .help("Swap panes")
            }
        }
    }

    @ViewBuilder
    private func paneView(tab: FileTab?, pane: AppState.Pane, label: String) -> some View {
        let isFocused = appState.focusedPane == pane

        VStack(spacing: 0) {
            if let tab = tab {
                MarkdownPaneView(pane: pane, tab: tab, splitContext: true)
            } else {
                // Empty pane placeholder
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("Open a markdown file to compare side by side")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("The next file you select will appear here")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(isFocused ? Color.clear : Color.primary.opacity(0.02))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(isFocused ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { appState.focusedPane = pane }
    }
}
