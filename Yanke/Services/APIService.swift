import Foundation

enum APIError: LocalizedError {
    case unsupportedFormat
    case invalidResponse(Int)
    case serverError(String)
    case noNotes

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:    return "Unsupported audio format. Use MP3, M4A, WAV, or FLAC."
        case .invalidResponse(let code): return "Server returned \(code). Is the backend running?"
        case .serverError(let msg):  return "Processing failed: \(msg)"
        case .noNotes:               return "No melody detected. Try a song with a clear vocal lead."
        }
    }
}

actor APIService {
    static let shared = APIService()

    private let baseURL = "http://localhost:8000"
    // 5-minute timeout: Demucs on CPU takes 1–3 min for a full song
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    func processAudio(fileURL: URL) async throws -> [Note] {
        let ext = fileURL.pathExtension.lowercased()
        guard ["mp3", "m4a", "wav", "aac", "flac"].contains(ext) else {
            throw APIError.unsupportedFormat
        }

        let url = URL(string: "\(baseURL)/process")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        // Access security-scoped resource (required for Files app picks)
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let audioData = try Data(contentsOf: fileURL)
        request.httpBody = buildMultipart(
            boundary: boundary,
            filename: fileURL.lastPathComponent,
            mimeType: mimeType(for: ext),
            data: audioData
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(0)
        }
        guard http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Unknown"
            throw APIError.serverError(msg)
        }

        let notes = try JSONDecoder().decode([Note].self, from: data)
        if notes.isEmpty { throw APIError.noNotes }
        return notes
    }

    // MARK: - Helpers

    private func buildMultipart(boundary: String, filename: String, mimeType: String, data: Data) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "mp3":  return "audio/mpeg"
        case "m4a":  return "audio/mp4"
        case "wav":  return "audio/wav"
        case "aac":  return "audio/aac"
        case "flac": return "audio/flac"
        default:     return "audio/mpeg"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
