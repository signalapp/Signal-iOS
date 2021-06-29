//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging
import WebRTC

/**
 * By default WebRTC starts the audio session (PlayAndRecord) immediately upon creating the peer connection
 * but we want to create the peer connection and set up all the signaling channels before we prompt the user
 * for an incoming call. Without manually handling the session, this would result in the user seeing a recording
 * permission requested (and recording banner) before they even know they have an incoming call.
 *
 * By using the `useManualAudio` and `isAudioEnabled` attributes of the RTCAudioSession we can delay recording until
 * it makes sense.
 */
extension OWSAudioSession {
    /**
     * The private class that manages AVAudioSession for WebRTC
     */
    private var rtcAudioSession: RTCAudioSession {
        return .sharedInstance()
    }

    /**
     * This must be called before any audio tracks are added to the peerConnection, else we'll start recording before all
     * our signaling is set up.
     */
    @objc
    public func configureRTCAudio() {
        Logger.info("")
        rtcAudioSession.useManualAudio = true
    }

    /**
     * Because we useManualAudio with our RTCAudioSession, we have to start/stop the recording audio session ourselves.
     * See header for details on  manual audio.
     */
    @objc
    public var isRTCAudioEnabled: Bool {
        get {
            return rtcAudioSession.isAudioEnabled
        }
        set {
            rtcAudioSession.isAudioEnabled = newValue
        }
    }
}
