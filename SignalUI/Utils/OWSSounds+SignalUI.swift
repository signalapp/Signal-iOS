//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension OWSSounds {

    private static func shouldAudioPlayerLoop(forSound sound: OWSSound) -> Bool {
        guard let sound = OWSStandardSound(rawValue: sound) else {
            return false
        }
        switch sound {
        case .callConnecting, .callOutboundRinging, .defaultiOSIncomingRingtone:
            return true
        default:
            return false
        }
    }

    @objc
    public static func audioPlayer(forSound sound: OWSSound, audioBehavior: OWSAudioBehavior) -> OWSAudioPlayer? {
        guard let soundUrl = OWSSounds.soundURL(forSound: sound, quiet: false) else {
            return nil
        }
        let player = OWSAudioPlayer(mediaUrl: soundUrl, audioBehavior: audioBehavior)
        if shouldAudioPlayerLoop(forSound: sound) {
            player.isLooping = true
        }
        return player
    }
}
