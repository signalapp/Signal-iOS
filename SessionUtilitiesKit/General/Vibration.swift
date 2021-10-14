import AudioToolbox

public final class Vibration {
    
    public static let shared = Vibration()
    
    private var vibrationTimer: Timer?
    
    public func startVibration() {
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
    
    public func stopVibrationIfPossible() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }
}
