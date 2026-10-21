import AVFoundation
import PulseCore

@MainActor
final class SessionChimes: NSObject, AVAudioPlayerDelegate {
    private var pending: [String] = []
    private var player: AVAudioPlayer?

    func play(_ sessionIDs: [String]) {
        pending.append(contentsOf: sessionIDs)
        if player == nil { playNext() }
    }
    func stop() {
        pending.removeAll()
        player?.stop()
        player = nil
    }
    private func playNext() {
        player = nil
        while !pending.isEmpty {
            let id = pending.removeFirst()
            guard let next = try? AVAudioPlayer(data: SessionChime.waveData(for: id)) else { continue }
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
