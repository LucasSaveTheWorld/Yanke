import Foundation

/// Converts an array of Note events into ABC notation for rendering with abcjs.
enum ABCConverter {

    // MARK: - Public

    static func convert(_ notes: [Note], title: String = "Melody") -> String {
        guard !notes.isEmpty else { return "" }

        let bpm       = estimateBPM(notes)
        let tickSec   = 60.0 / (bpm * 4)   // duration of one sixteenth note in seconds
        let ticksPerMeasure = 16            // 4/4 time = 16 sixteenth notes

        var tokens: [String] = []
        var cursor = 0.0   // current time position in ticks

        for note in notes.sorted(by: { $0.startTime < $1.startTime }) {
            let startTick = max(0, Int((note.startTime / tickSec).rounded()))
            let durTick   = max(1, Int((note.duration  / tickSec).rounded()))

            // Insert rest if there's a gap
            let gap = startTick - Int(cursor.rounded())
            if gap > 0 { tokens.append(rest(ticks: gap)) }

            tokens.append(abcNote(midi: note.midiPitch, ticks: durTick))
            cursor = Double(startTick + durTick)
        }

        // Group tokens into measures with bar lines
        let abc = buildABC(
            tokens: tokens,
            ticksPerMeasure: ticksPerMeasure,
            bpm: bpm,
            title: title
        )
        return abc
    }

    // MARK: - Tempo estimation

    private static func estimateBPM(_ notes: [Note]) -> Double {
        // Use median note duration and assume it's roughly a quarter note
        let sorted = notes.map(\.duration).sorted()
        let median = sorted[sorted.count / 2]
        let bpm = (60.0 / median).clamped(to: 50...180)
        return (bpm / 10).rounded() * 10   // round to nearest 10 bpm
    }

    // MARK: - ABC pitch encoding

    private static func abcNote(midi: Int, ticks: Int) -> String {
        let noteNames = ["C", "^C", "D", "^D", "E", "F", "^F", "G", "^G", "A", "^A", "B"]
        let pc      = midi % 12
        let octave  = (midi / 12) - 1   // MIDI 60 = C4 = octave 4

        let baseName = noteNames[pc]  // may include accidental prefix (^/_)

        // Separate any accidental from the letter for case transformation
        let (accidental, letter) = splitAccidental(baseName)

        let abcLetter: String
        switch octave {
        case ...3:  // C3 and below
            let commas = String(repeating: ",", count: max(0, 4 - octave))
            abcLetter = accidental + letter + commas
        case 4:
            abcLetter = accidental + letter
        case 5:
            abcLetter = accidental + letter.lowercased()
        case 6:
            abcLetter = accidental + letter.lowercased() + "'"
        default:    // 7+
            let primes = String(repeating: "'", count: octave - 5)
            abcLetter = accidental + letter.lowercased() + primes
        }

        return abcLetter + durationSuffix(ticks: ticks)
    }

    private static func rest(ticks: Int) -> String {
        return "z" + durationSuffix(ticks: ticks)
    }

    private static func durationSuffix(ticks: Int) -> String {
        // L:1/16 → 1 tick = one sixteenth note (no suffix)
        switch ticks {
        case 1:  return ""       // 1/16
        case 2:  return "2"      // 1/8
        case 3:  return "3"      // dotted 1/8
        case 4:  return "4"      // 1/4
        case 6:  return "6"      // dotted 1/4
        case 8:  return "8"      // 1/2
        case 12: return "12"     // dotted 1/2
        case 16: return "16"     // whole
        default: return ticks > 1 ? "\(ticks)" : ""
        }
    }

    private static func splitAccidental(_ name: String) -> (String, String) {
        if name.hasPrefix("^") { return ("^", String(name.dropFirst())) }
        if name.hasPrefix("_") { return ("_", String(name.dropFirst())) }
        return ("", name)
    }

    // MARK: - Measure assembly

    private static func buildABC(
        tokens: [String],
        ticksPerMeasure: Int,
        bpm: Double,
        title: String
    ) -> String {
        // Distribute tokens into measures based on their tick lengths
        var measures: [[String]] = []
        var current: [String] = []
        var currentTicks = 0

        for token in tokens {
            let t = tokenTicks(token)

            if currentTicks + t > ticksPerMeasure && !current.isEmpty {
                // Pad measure with rest if needed
                let remaining = ticksPerMeasure - currentTicks
                if remaining > 0 { current.append(rest(ticks: remaining)) }
                measures.append(current)
                current = []
                currentTicks = 0
            }

            // If a single token is longer than a measure, split isn't easy — just append
            current.append(token)
            currentTicks += t

            if currentTicks == ticksPerMeasure {
                measures.append(current)
                current = []
                currentTicks = 0
            }
        }
        if !current.isEmpty { measures.append(current) }

        // Build ABC string
        let header = """
X:1
T:\(title)
M:4/4
L:1/16
Q:1/4=\(Int(bpm))
K:C clef=treble
"""
        // Split into lines of ~4 measures each for readability
        let measureStrings = measures.map { $0.joined() }
        var lines: [String] = []
        let measuresPerLine = 4
        stride(from: 0, to: measureStrings.count, by: measuresPerLine).forEach { i in
            let chunk = measureStrings[i..<min(i + measuresPerLine, measureStrings.count)]
            lines.append(chunk.joined(separator: " | "))
        }

        return header + "\n" + lines.map { "| \($0) |" }.joined(separator: "\n")
    }

    private static func tokenTicks(_ token: String) -> Int {
        // Parse duration from token suffix (z4, C8, ^D2, etc.)
        let stripped = token
            .replacingOccurrences(of: "^", with: "")
            .replacingOccurrences(of: "_", with: "")
        let digits = stripped.filter(\.isNumber)
        return Int(digits) ?? 1
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
