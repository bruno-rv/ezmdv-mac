import SwiftUI

struct TOCHeading: Identifiable {
    let id = UUID()
    let level: Int
    let text: String
    let anchor: String
}

struct TOCView: View {
    let headings: [TOCHeading]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.bullet")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("TABLE OF CONTENTS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(headings) { heading in
                        Button(action: { onSelect(heading.anchor) }) {
                            Text(heading.text)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, CGFloat((heading.level - 1) * 12))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 220)
        .background(.bar)
        .overlay(alignment: .leading) {
            Divider()
        }
    }
}
