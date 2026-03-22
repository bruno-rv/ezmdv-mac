import SwiftUI

struct FindBar: View {
    @Binding var query: String
    @Binding var replaceText: String
    @Binding var showReplace: Bool
    let editorMode: String        // "view" | "edit" | "preview"
    let matchCurrent: Int         // 1-based index of current match, 0 = none
    let matchTotal: Int           // total match count, -1 = not yet known
    let onFindNext: () -> Void
    let onFindPrev: () -> Void
    let onQueryChanged: (String) -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            // Row 1: Find
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Find", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($queryFocused)
                    .onSubmit { onFindNext() }

                matchLabel

                Divider().frame(height: 14)

                Button(action: onFindPrev) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Previous Match (⌘⇧G)")
                .disabled(query.isEmpty)

                Button(action: onFindNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Next Match (⌘G)")
                .disabled(query.isEmpty)

                Divider().frame(height: 14)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            // Row 2: Replace (only when showReplace && in edit mode)
            if showReplace && editorMode == "edit" {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("Replace", text: $replaceText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { onReplace() }

                    Divider().frame(height: 14)

                    Button("Replace", action: onReplace)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .disabled(query.isEmpty)

                    Button("Replace All", action: onReplaceAll)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .disabled(query.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
        }
        .background(.bar)
        .onAppear { queryFocused = true }
        .onExitCommand { onClose() }
        .onChange(of: query) { _, newValue in
            onQueryChanged(newValue)
        }
    }

    @ViewBuilder
    private var matchLabel: some View {
        if !query.isEmpty {
            if matchTotal == 0 {
                Text("No matches")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else if matchTotal > 0 {
                Text("\(matchCurrent) of \(matchTotal)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            // matchTotal == -1: search pending, show nothing
        }
    }
}
