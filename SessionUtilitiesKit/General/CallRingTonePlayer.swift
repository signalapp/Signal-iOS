import AudioToolbox
import AVFoundation

public final class CallRingTonePlayer {
    
    public static let shared = CallRingTonePlayer()
    
    private var vibrationTimer: Timer?
    private var player: AVAudioPlayer?
    
    public func startVibration() {
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
    
    public func stopVibrationIfPossible() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }
    
    public func startPlayingRingTone() {
        guard let url = Bundle.main.url(forResource: "ringing", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)
            player?.numberOfLoops = -1
            player?.play()
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    public func stopPlayingRingTone() {
        guard let player = player else { return }
        player.stop()
    }
}
