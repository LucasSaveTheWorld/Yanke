import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    let errorMessage: String?
    let onFilePicked: (URL) -> Void

    @State private var showFilePicker = false

    private let audioTypes: [UTType] = [
        .audio, .mp3,
        UTType("public.mpeg-4-audio") ?? .audio,
        UTType("com.microsoft.waveform-audio") ?? .audio,
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 10) {
                Text("燕歌")
                    .font(.system(size: 72, weight: .ultraLight, design: .serif))
                    .foregroundStyle(.primary)
                Text("Piano Melody · 主旋律")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }

            Spacer()

            // Import button
            VStack(spacing: 16) {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Import Song", systemImage: "music.note")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                Text("Supports MP3, M4A, WAV, FLAC")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // DEV ONLY: load test.m4a from app Documents
                #if DEBUG
                if let testURL = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("test.m4a"),
                   FileManager.default.fileExists(atPath: testURL.path) {
                    Button("⚙️ Load test.m4a") { onFilePicked(testURL) }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
            }
            .padding(.horizontal, 40)

            // Error banner
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(.red)
                .padding()
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            Spacer().frame(height: 60)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: audioTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                onFilePicked(url)
            case .failure:
                break // user cancelled
            }
        }
    }
}
