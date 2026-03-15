import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Binding var incomingURL: URL?
    @State private var phase: AppPhase = .home
    @State private var errorMessage: String?

    enum AppPhase {
        case home
        case processing(fileName: String)
        case result(notes: [Note], fileName: String)
    }

    var body: some View {
        NavigationStack {
            switch phase {
            case .home:
                HomeView(errorMessage: errorMessage) { url in
                    startProcessing(url: url)
                }

            case .processing(let fileName):
                ProcessingView(fileName: fileName)

            case .result(let notes, let fileName):
                PianoRollView(notes: notes, fileName: fileName)
                    .navigationTitle("燕歌")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("New Song") { phase = .home }
                        }
                    }
            }
        }
        .onChange(of: incomingURL) { _, url in
            guard let url else { return }
            incomingURL = nil
            startProcessing(url: url)
        }
    }

    private func startProcessing(url: URL) {
        let fileName = url.deletingPathExtension().lastPathComponent
        phase = .processing(fileName: fileName)
        errorMessage = nil

        Task {
            do {
                let notes = try await APIService.shared.processAudio(fileURL: url)
                await MainActor.run { phase = .result(notes: notes, fileName: fileName) }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    phase = .home
                }
            }
        }
    }
}
