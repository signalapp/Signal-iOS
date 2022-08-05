//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFAudio

@objc
public class SpeechManager: NSObject {
    private let speechSynthesizer: AVSpeechSynthesizer

    @objc
    override init() {
        speechSynthesizer = AVSpeechSynthesizer()

        super.init()

        SwiftSingletons.register(self)
    }

    @objc
    public var isSpeaking: Bool {
        speechSynthesizer.isSpeaking
    }

    @objc
    public func speak(_ utterance: AVSpeechUtterance) {
        speechSynthesizer.speak(utterance)
    }

    @objc
    public func stop() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }
}
