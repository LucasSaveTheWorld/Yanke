import SwiftUI

struct PianoRollView: View {
    let notes: [Note]
    let fileName: String

    // Display range: clamp to actual pitch range + padding
    private var minPitch: Int { max(21, (notes.map(\.midiPitch).min() ?? 60) - 4) }
    private var maxPitch: Int { min(108, (notes.map(\.midiPitch).max() ?? 72) + 4) }
    private var pitchRange: Int { maxPitch - minPitch + 1 }

    private var totalDuration: Double {
        notes.map { $0.startTime + $0.duration }.max() ?? 1
    }

    // Pixels per second of audio
    private let pxPerSecond: CGFloat = 100
    private let rowHeight: CGFloat = 10
    private let labelWidth: CGFloat = 30

    private var rollWidth: CGFloat { CGFloat(totalDuration) * pxPerSecond }
    private var rollHeight: CGFloat { CGFloat(pitchRange) * rowHeight }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            VStack(spacing: 2) {
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(notes.count) notes · \(String(format: "%.1f", totalDuration))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)

            Divider()

            // Piano roll
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                HStack(spacing: 0) {
                    // Left: pitch labels
                    PitchLabelColumn(
                        minPitch: minPitch,
                        maxPitch: maxPitch,
                        rowHeight: rowHeight,
                        width: labelWidth
                    )

                    // Right: roll canvas
                    Canvas { context, size in
                        drawBackground(context: context, size: size)
                        drawNotes(context: context, size: size)
                    }
                    .frame(width: rollWidth, height: rollHeight)
                }
                .frame(height: rollHeight)
            }
            .background(Color(white: 0.1))

            Divider()

            // Bottom hint
            Text("Scroll to explore · Higher rows = higher pitch")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Drawing

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        let blackKeyIndices: Set<Int> = [1, 3, 6, 8, 10]

        for i in 0..<pitchRange {
            let pitch = maxPitch - i
            let isBlack = blackKeyIndices.contains(pitch % 12)
            let y = CGFloat(i) * rowHeight

            context.fill(
                Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)),
                with: .color(isBlack ? Color(white: 0.08) : Color(white: 0.14))
            )

            // Horizontal line at each C
            if pitch % 12 == 0 {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.white.opacity(0.2)), lineWidth: 0.5)
            }
        }

        // Vertical beat lines (assuming 120 BPM for visual reference)
        let beatInterval = pxPerSecond * 0.5 // 0.5s = 120bpm beat
        var x: CGFloat = 0
        while x < size.width {
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            x += beatInterval
        }
    }

    private func drawNotes(context: GraphicsContext, size: CGSize) {
        for note in notes {
            let x = CGFloat(note.startTime) * pxPerSecond
            let w = max(CGFloat(note.duration) * pxPerSecond, 4)
            let row = maxPitch - note.midiPitch
            guard row >= 0 && row < pitchRange else { continue }
            let y = CGFloat(row) * rowHeight + 1

            let rect = CGRect(x: x, y: y, width: w, height: rowHeight - 2)
            let path = Path(roundedRect: rect, cornerRadius: 2)

            // Color by pitch class (chromatic wheel)
            let hue = Double(note.midiPitch % 12) / 12.0
            context.fill(path, with: .color(Color(hue: hue, saturation: 0.75, brightness: 0.95)))
        }
    }
}

// MARK: - Pitch label sidebar

struct PitchLabelColumn: View {
    let minPitch: Int
    let maxPitch: Int
    let rowHeight: CGFloat
    let width: CGFloat

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        VStack(spacing: 0) {
            ForEach((minPitch...maxPitch).reversed(), id: \.self) { pitch in
                ZStack {
                    Color(white: pitch % 12 == 0 ? 0.18 : 0.12)
                    if pitch % 12 == 0 {
                        let octave = (pitch / 12) - 1
                        Text("C\(octave)")
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(width: width, height: rowHeight)
            }
        }
    }
}
