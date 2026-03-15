import SwiftUI

struct ProcessingView: View {
    let fileName: String

    @State private var elapsed: Int = 0
    @State private var stage: String = "Uploading…"

    // Rough stage labels keyed by elapsed seconds (Demucs ~60–180s, CREPE ~10–30s)
    private let stageTimeline: [(Int, String)] = [
        (0,   "Uploading…"),
        (3,   "Separating vocals with Demucs…"),
        (90,  "Tracking pitch with CREPE…"),
        (120, "Quantizing to notes…"),
        (150, "Almost there…"),
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ProgressView()
                .scaleEffect(1.6)
                .tint(.indigo)

            VStack(spacing: 8) {
                Text(stage)
                    .font(.headline)
                    .animation(.easeInOut, value: stage)

                Text(fileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(formattedElapsed)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Spacer()

            Text("Processing on your Mac's CPU.\nThis typically takes 1–3 minutes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)
        }
        .padding()
        .onAppear { startTimer() }
    }

    private var formattedElapsed: String {
        let m = elapsed / 60
        let s = elapsed % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed += 1
            // Update stage label
            let label = stageTimeline.last(where: { $0.0 <= elapsed })?.1 ?? stage
            if label != stage { stage = label }
        }
    }
}
