//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AVFoundation
import SignalServiceKit

public struct AudioSource: Hashable, CustomDebugStringConvertible {

    public let localizedName: String
    public let portDescription: AVAudioSessionPortDescription?

    // The built-in loud speaker / aka speakerphone
    public let isBuiltInSpeaker: Bool

    // The built-in quiet speaker, aka the normal phone handset receiver earpiece
    public let isBuiltInEarPiece: Bool

    public init(localizedName: String, isBuiltInSpeaker: Bool, isBuiltInEarPiece: Bool, portDescription: AVAudioSessionPortDescription? = nil) {
        self.localizedName = localizedName
        self.isBuiltInSpeaker = isBuiltInSpeaker
        self.isBuiltInEarPiece = isBuiltInEarPiece
        self.portDescription = portDescription
    }

    public init(portDescription: AVAudioSessionPortDescription) {

        let isBuiltInEarPiece = portDescription.portType == AVAudioSession.Port.builtInMic

        // portDescription.portName works well for BT linked devices, but if we are using
        // the built in mic, we have "iPhone Microphone" which is a little awkward.
        // In that case, instead we prefer just the model name e.g. "iPhone" or "iPad"
        let localizedName = isBuiltInEarPiece ? UIDevice.current.localizedModel : portDescription.portName

        self.init(localizedName: localizedName,
                  isBuiltInSpeaker: false,
                  isBuiltInEarPiece: isBuiltInEarPiece,
                  portDescription: portDescription)
    }

    // Speakerphone is handled separately from the other audio routes as it doesn't appear as an "input"
    public static var builtInSpeaker: AudioSource {
        return self.init(localizedName: OWSLocalizedString("AUDIO_ROUTE_BUILT_IN_SPEAKER", comment: "action sheet button title to enable built in speaker during a call"),
                         isBuiltInSpeaker: true,
                         isBuiltInEarPiece: false)
    }

    // MARK: Hashable

    public static func == (lhs: AudioSource, rhs: AudioSource) -> Bool {
        // Simply comparing the `portDescription` vs the `portDescription.uid`
        // caused multiple instances of the built in mic to turn up in a set.
        if lhs.isBuiltInSpeaker && rhs.isBuiltInSpeaker {
            return true
        }

        if lhs.isBuiltInSpeaker || rhs.isBuiltInSpeaker {
            return false
        }

        guard let lhsPortDescription = lhs.portDescription else {
            owsFailDebug("only the built in speaker should lack a port description")
            return false
        }

        guard let rhsPortDescription = rhs.portDescription else {
            owsFailDebug("only the built in speaker should lack a port description")
            return false
        }

        return lhsPortDescription.uid == rhsPortDescription.uid
    }

    public func hash(into hasher: inout Hasher) {
        guard let portDescription = self.portDescription else {
            assert(self.isBuiltInSpeaker)
            hasher.combine("Built In Speaker")
            return
        }

        hasher.combine(portDescription.uid)
    }

    public var debugDescription: String {
        guard let portDescription = self.portDescription else {
            assert(self.isBuiltInSpeaker)
            return "<built-in speaker>"
        }
        return portDescription.logSafeDescription
    }
}

extension AVAudioSessionPortDescription {
    var logSafeDescription: String {
        let portName = self.portName
        if portName.dropFirst(4).isEmpty {
            return "<\(portType): \(portName)>"
        }
        return "<\(portType): \(portName.prefix(2))..\(portName.suffix(2))>"
    }
}
