import Foundation
import Testing
@testable import PulseCore

struct SessionChimeTests {
    @Test func mappingIsStableAndUsesTheCompleteProviderQualifiedID() {
        // Fixed fixtures catch accidental changes to the mapping between app versions.
        #expect(SessionChime.note(for: "codex:one") == 70)
        #expect(SessionChime.note(for: "claude:one") == 65)
        #expect(SessionChime.note(for: "codex:01a15ba9-592e-7022-84a3-bebf531f07d0") == 83)
        let notes = (0..<240).map { SessionChime.note(for: "codex:session-\($0)") }
        #expect(notes.allSatisfy { (60...83).contains($0) })
        #expect(Set(notes).count == 24)
    }
    @Test func waveIsValidQuietPCMWithSoftEdges() {
        let data = SessionChime.waveData(for: "codex:one")
        #expect(data == SessionChime.waveData(for: "codex:one"))
        #expect(data != SessionChime.waveData(for: "claude:one"))
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(data[20] == 1 && data[22] == 1 && data[34] == 16)
        let count = Int(Double(SessionChime.sampleRate) * SessionChime.duration)
        #expect(data.count == 44 + count * 2)
        let samples = stride(from: 44, to: data.count, by: 2).map {
            Int(Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8))
        }
        #expect(samples.first == 0)
        #expect(abs(samples.last ?? 999) < 20)
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 1000 && peak < 13000)
        // Two audible attacks separated by a dip, followed by a quiet tail.
        func rms(_ start: Double, _ end: Double) -> Double {
            let range = Int(start * Double(SessionChime.sampleRate))..<Int(end * Double(SessionChime.sampleRate))
            return sqrt(range.reduce(0.0) { $0 + pow(Double(samples[$1]), 2) } / Double(range.count))
        }
        #expect(rms(0.01, 0.05) > rms(0.15, 0.18) * 3)
        #expect(rms(0.20, 0.24) > rms(0.15, 0.18) * 3)
        #expect(rms(0.50, 0.55) < rms(0.20, 0.24) / 10)
        #expect((260...990).contains(SessionChime.frequency(for: "codex:one")))
    }
}
