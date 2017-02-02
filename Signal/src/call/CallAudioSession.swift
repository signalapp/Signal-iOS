//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC

/**
 * By default WebRTC starts the audio session (PlayAndRecord) immediately upon creating the peer connection
 * but we want to create the peer connection and set up all the signaling channels before we prompt the user
 * for an incoming call. Without manually handling the session, this would result in the user seeing a recording
 * permission requested (and recording banner) before they even know they have an incoming call.
 *
 * By using the `useManualAudio` and `isAudioEnabled` attributes of the RTCAudioSession we can delay recording until
 * it makes sense. However, the headers for RTCAudioSession are not exported by default, so we've vendored the header
 * into our project. See "Libraries/WebRTC"
 */
class CallAudioSession {

    let TAG = "[CallAudioSession]"
    /**
     * The private class that manages AVAudioSession for WebRTC
     */
    private let rtcAudioSession = RTCAudioSession.sharedInstance()


    /**
    * This must be called before any audio tracks are added to the peerConnection, else we'll start recording before all
    * our signaling is set up.
    */
    func configure() {
        Logger.info("\(TAG) in \(#function)")
        rtcAudioSession.useManualAudio = true
    }

    /**
     * Because we useManualAudio with our RTCAudioSession, we have to start the recording audio session ourselves.
     */
    func start() {
        Logger.info("\(TAG) in \(#function)")
        rtcAudioSession.isAudioEnabled = true
    }

    /**
     * Because we useManualAudio with our RTCAudioSession, we have to stop the recording audio session ourselves.
     * Else, we start recording before the next call is ringing.
     */
    func stop() {
        Logger.info("\(TAG) in \(#function)")
        rtcAudioSession.isAudioEnabled = false
    }
}
