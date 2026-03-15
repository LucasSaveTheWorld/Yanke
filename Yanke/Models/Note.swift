import Foundation

struct Note: Codable, Identifiable {
    let midiPitch: Int
    let startTime: Double
    let duration: Double
    let noteName: String

    // Synthesized locally — not part of API response
    var id: String { "\(midiPitch)-\(startTime)" }
}
