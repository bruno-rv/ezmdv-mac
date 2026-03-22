import SwiftUI

struct SiteExportProgressView: View {
    let totalFiles: Int
    @Binding var completedFiles: Int
    @Binding var currentFileName: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Exporting Vault…")
                .font(.headline)

            ProgressView(value: totalFiles > 0 ? Double(completedFiles) / Double(totalFiles) : 0)
                .progressViewStyle(.linear)
                .frame(width: 320)

            Text("\(completedFiles) / \(totalFiles) files")
                .font(.caption)
                .foregroundColor(.secondary)

            if !currentFileName.isEmpty {
                Text(currentFileName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 320)
            }

            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(minWidth: 380)
    }
}
