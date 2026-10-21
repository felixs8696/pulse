import AVFoundation
import PulseCore

@MainActor
final class SessionChimes: NSObject, AVAudioPlayerDelegate {
    private var pending: [(id: String, tone: Int?)] = []
    private var player: AVAudioPlayer?
    private var previewPlayer: AVAudioPlayer?

    func preview(_ sessionID: String, tone: Int?) {
        previewPlayer?.stop()
        previewPlayer = try? AVAudioPlayer(data: SessionChime.waveData(for: sessionID, tone: tone))
        previewPlayer?.volume = 0.85
        previewPlayer?.play()
    }

    func play(_ sessionIDs: [String], tones: [String: Int] = [:]) {
        pending.append(contentsOf: sessionIDs.map { (id: $0, tone: tones[$0]) })
        if player == nil { playNext() }
    }
    func stop() {
        pending.removeAll()
        player?.stop()
        player = nil
        previewPlayer?.stop()
        previewPlayer = nil
    }
    private func playNext() {
        player = nil
        while !pending.isEmpty {
            let sound = pending.removeFirst()
            guard let next = try? AVAudioPlayer(data: SessionChime.waveData(for: sound.id, tone: sound.tone)) else { continue }
            next.delegate = self
            next.volume = 0.85
            next.prepareToPlay()
            player = next
            if next.play() { return }
            player = nil
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.playNext()
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.playNext()
        }
    }
}
