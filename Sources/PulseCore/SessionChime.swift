import Foundation

/// Stable across app launches and machines (Swift's built-in Hasher is randomized).
public enum SessionChime {
    public static func note(for sessionID: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in sessionID.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        // Two octaves, C4–B5: distinct pitches without very low or piercing tones.
        return 60 + Int(hash % 24)
    }
    public static func frequency(for sessionID: String) -> Double {
        440 * pow(2, Double(note(for: sessionID) - 69) / 12)
    }
    public static let sampleRate = 44_100
    public static let duration = 0.62

    /// Two rounded wooden taps, a major third apart, with a short shared tail.
    /// Harmonic overtones keep the sound warm even for higher session pitches.
    public static func waveData(for sessionID: String) -> Data {
        let frequency = frequency(for: sessionID)
        let count = Int(Double(sampleRate) * duration)
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func word(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func dword(_ value: UInt32) {
            word(UInt16(truncatingIfNeeded: value)); word(UInt16(truncatingIfNeeded: value >> 16))
        }
        ascii("RIFF"); dword(UInt32(36 + count * 2)); ascii("WAVEfmt "); dword(16)
        word(1); word(1); dword(UInt32(sampleRate)); dword(UInt32(sampleRate * 2)); word(2); word(16)
        ascii("data"); dword(UInt32(count * 2))
        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            func tap(at onset: Double, ratio: Double, gain: Double) -> Double {
                let elapsed = time - onset
                guard elapsed >= 0, elapsed < 0.40 else { return 0 }
                let attack = min(1, elapsed / 0.006)
                let release = min(1, (0.40 - elapsed) / 0.045)
                let phase = 2 * Double.pi * frequency * ratio * elapsed
                let tone = sin(phase) * exp(-13 * elapsed)
                    + 0.16 * sin(2 * phase) * exp(-23 * elapsed)
                    + 0.035 * sin(3 * phase) * exp(-32 * elapsed)
                return tone * attack * release * gain
            }
            let tone = tap(at: 0, ratio: 1, gain: 1)
                + tap(at: 0.19, ratio: pow(2, 4.0 / 12), gain: 0.92)
            let sample = Int16((tone * 0.28 * Double(Int16.max)).rounded())
            word(UInt16(bitPattern: sample))
        }
        return data
    }
}
