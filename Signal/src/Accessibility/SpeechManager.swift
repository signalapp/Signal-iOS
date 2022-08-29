//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import AVFAudio

@objc
public class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    private let speechSynthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        SwiftSingletons.register(self)
    }

    deinit {
        stopListeningToEvents()
    }

    public var isSpeaking: Bool {
        speechSynthesizer.isSpeaking
    }

    public func speak(_ utterance: AVSpeechUtterance) {
        stop()
        speechSynthesizer.speak(utterance)
    }

    @objc
    public func stop() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    public func speechSynthesizer(_: AVSpeechSynthesizer, didStart: AVSpeechUtterance) { listenToApplicationDidEnterBackgroundEvent() }
    public func speechSynthesizer(_: AVSpeechSynthesizer, didPause: AVSpeechUtterance) { stopListeningToEvents() }
    public func speechSynthesizer(_: AVSpeechSynthesizer, didContinue: AVSpeechUtterance) { listenToApplicationDidEnterBackgroundEvent() }
    public func speechSynthesizer(_: AVSpeechSynthesizer, didFinish: AVSpeechUtterance) { stopListeningToEvents() }
    public func speechSynthesizer(_: AVSpeechSynthesizer, didCancel: AVSpeechUtterance) { stopListeningToEvents() }

    private func listenToApplicationDidEnterBackgroundEvent() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stop),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
    }

    private func stopListeningToEvents() {
        NotificationCenter.default.removeObserver(self)
    }
}
