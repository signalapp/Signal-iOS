//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC

@objc
public class OWSAudioSession: NSObject {

    // Force singleton access
    public static let shared = OWSAudioSession()
    private override init() {}
    private let avAudioSession = AVAudioSession.sharedInstance()

    //
    ///*  Use this category for background sounds such as rain, car engine noise, etc.
    // Mixes with other music. */
    //AVF_EXPORT NSString *const AVAudioSessionCategoryAmbient;
    //
    ///*  Use this category for background sounds.  Other music will stop playing. */
    //AVF_EXPORT NSString *const AVAudioSessionCategorySoloAmbient;
    //
    ///* Use this category for music tracks.*/
    //AVF_EXPORT NSString *const AVAudioSessionCategoryPlayback;
    //
    ///*  Use this category when recording audio. */
    //AVF_EXPORT NSString *const AVAudioSessionCategoryRecord;
    //
    ///*  Use this category when recording and playing back audio. */
    //AVF_EXPORT NSString *const AVAudioSessionCategoryPlayAndRecord;
    //
    ///*  Use this category when using a hardware codec or signal processor while
    // not playing or recording audio. */
    //AVF_EXPORT NSString *const AVAudioSessionCategoryAudioProcessing

    // Ignores hardware mute switch, plays through external speaker
    public func setPlaybackCategory() {
        Logger.debug("\(logTag) in \(#function)")
        do {
            try avAudioSession.setCategory(AVAudioSessionCategoryPlayback)
        } catch {
            owsFail("\(logTag) in \(#function) failed with error: \(error)")
        }
    }

    public func endAudioActivity() {
        Logger.debug("\(logTag) in \(#function)")
        do {
            try avAudioSession.setCategory(AVAudioSessionCategoryAmbient)

            // When playing audio in Signal, other apps audio (e.g. Music) is paused.
            // By notifying when we deactivate, the other app can resume playback.
            try avAudioSession.setActive(false, with: [.notifyOthersOnDeactivation])
        } catch {
            owsFail("\(logTag) in \(#function) failed with error: \(error)")
        }
    }

    // MARK: - WebRTC Audio

    /**
     * By default WebRTC starts the audio session (PlayAndRecord) immediately upon creating the peer connection
     * but we want to create the peer connection and set up all the signaling channels before we prompt the user
     * for an incoming call. Without manually handling the session, this would result in the user seeing a recording
     * permission requested (and recording banner) before they even know they have an incoming call.
     *
     * By using the `useManualAudio` and `isAudioEnabled` attributes of the RTCAudioSession we can delay recording until
     * it makes sense.
     */

    /**
     * The private class that manages AVAudioSession for WebRTC
     */
    private let rtcAudioSession = RTCAudioSession.sharedInstance()

    /**
     * This must be called before any audio tracks are added to the peerConnection, else we'll start recording before all
     * our signaling is set up.
     */
    public func configureRTCAudio() {
        Logger.info("\(logTag) in \(#function)")
        rtcAudioSession.useManualAudio = true
    }

    /**
     * Because we useManualAudio with our RTCAudioSession, we have to start/stop the recording audio session ourselves.
     * See header for details on  manual audio.
     */
    public var isRTCAudioEnabled: Bool {
        get {
            return rtcAudioSession.isAudioEnabled
        }
        set {
            rtcAudioSession.isAudioEnabled = newValue
        }
    }
}
