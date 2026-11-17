import AppKit
import SwiftUI
import WallVueCore

/// Turns a video into one that repeats without a visible jump: pick where
/// it starts and ends, and how long the blend between the two lasts.
struct LoopMakerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let wallpaper: Wallpaper

    @State private var start = 0.0
    @State private var end = 0.0
    @State private var fade = 1.0
    @State private var startFrame: NSImage?
    @State private var endFrame: NSImage?

    private var duration: Double { wallpaper.duration }
    private var plan: LoopPlan { LoopPlan(start: start, end: end, fade: fade).clamped(toDuration: duration) }

    /// Identifies the two frames on show, so they reload when a slider moves.
    private var frameKey: String { String(format: "%.2f-%.2f", plan.start, plan.end) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make a Seamless Loop")
                    .font(.title2.weight(.bold))
                Text("WallVue trims “\(wallpaper.title)” and blends its end into its beginning, so you can't see where it repeats. The original stays in your Library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                framePreview(startFrame, caption: "Starts here", time: plan.start)
                framePreview(endFrame, caption: "Ends here", time: plan.end)
            }
            Text("The more alike these two frames look, the smoother the loop.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                sliderRow("Start", value: $start, range: 0...max(duration - LoopPlan.minimumSpan, 0.01), label: Self.clock(plan.start))
                sliderRow("End", value: $end, range: min(LoopPlan.minimumSpan, duration)...max(duration, LoopPlan.minimumSpan + 0.01), label: Self.clock(plan.end))
                sliderRow("Blend", value: $fade, range: 0...LoopPlan.maximumFade, label: String(format: "%.1f s", plan.fade))
            }

            HStack {
                Label("Loop length \(Self.clock(plan.outputDuration))", systemImage: "repeat")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Make Loop") {
                    model.makeLoop(of: wallpaper, plan: plan)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600)
        .onAppear {
            let suggestion = LoopPlan.suggested(forDuration: duration)
            start = suggestion.start
            end = suggestion.end
            fade = suggestion.fade
        }
        // Keep the two ends a loop's length apart as either slider moves.
        .onChange(of: start) { _, value in
            if end < value + LoopPlan.minimumSpan { end = min(duration, value + LoopPlan.minimumSpan) }
        }
        .onChange(of: end) { _, value in
            if start > value - LoopPlan.minimumSpan { start = max(0, value - LoopPlan.minimumSpan) }
        }
        .task(id: frameKey) {
            // Wait for the slider to settle before decoding frames.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let current = plan
            // A hair inside the end, so the last frame is always decodable.
            let lastMoment = max(current.start, current.end - 0.05)
            async let first = MediaTools.frame(of: wallpaper.fileURL, at: current.start, maxDimension: 640)
            async let last = MediaTools.frame(of: wallpaper.fileURL, at: lastMoment, maxDimension: 640)
            let images = (try? await first, try? await last)
            guard !Task.isCancelled else { return }
            startFrame = images.0.map { NSImage(cgImage: $0, size: .zero) }
            endFrame = images.1.map { NSImage(cgImage: $0, size: .zero) }
        }
    }

    private func framePreview(_ image: NSImage?, caption: String, time: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("\(caption) · \(Self.clock(time))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption), \(Self.clock(time))")
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(label)
            Text(label)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .font(.callout)
    }

    /// "0:07.5"
    private static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds)
        let tenths = Int(((seconds - Double(whole)) * 10).rounded(.down))
        return String(format: "%d:%02d.%d", whole / 60, whole % 60, tenths)
    }
}
