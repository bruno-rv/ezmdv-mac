import SwiftUI

struct AutoScrollButton: View {
    @Binding var active: Bool
    @Binding var intervalSeconds: Double
    @Binding var scrollPercent: Double
    let onToggle: () -> Void

    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 0) {
            // Play / Pause button
            Button(action: onToggle) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: active ? "pause.fill" : "play.fill")
                        .font(.system(size: 10))
                        .frame(width: 26, height: 22)
                        .foregroundStyle(active ? Color.accentColor : .secondary)

                    if active {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 5, height: 5)
                            .offset(x: -2, y: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(active ? "Pause autoscroll" : "Start autoscroll")

            // Settings chevron
            Button(action: { showPopover.toggle() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .frame(width: 14, height: 22)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showPopover ? 180 : 0))
            }
            .buttonStyle(.plain)
            .help("Autoscroll settings")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                AutoScrollSettingsPopover(
                    intervalSeconds: $intervalSeconds,
                    scrollPercent: $scrollPercent
                )
            }
        }
        .background(active ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct AutoScrollSettingsPopover: View {
    @Binding var intervalSeconds: Double
    @Binding var scrollPercent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Autoscroll Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            // Speed slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Speed")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("\(Int(intervalSeconds))s")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $intervalSeconds, in: 1...120, step: 1)
                    .controlSize(.small)
                HStack {
                    Text("1s (fast)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("120s (slow)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            // Scroll amount slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scroll amount")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("\(Int(scrollPercent))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $scrollPercent, in: 1...100, step: 1)
                    .controlSize(.small)
                HStack {
                    Text("1% (small)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("100% (full page)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}
