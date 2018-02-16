//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

import XCTest
import AVKit
import WebRTC

/**
 * These tests are obtuse - they just assert the exact implementation of the methods. Normally I wouldn't include them, 
 * but these methods make use of a header not included in the standard distribution of the WebRTC.framework. We've 
 * included the header in our local project, and test the methods here to make sure that they are still available when 
 * we upgrade the framework. 
 *
 * If they are failing, it's possible the RTCAudioSession header, and our usage of it, need to be updated.
 */
class CallAudioSessionTest: XCTestCase {
    func testAudioSession() {

        let rtcAudioSession = RTCAudioSession.sharedInstance()
        // Sanity Check
        XCTAssertFalse(rtcAudioSession.useManualAudio)

        CallAudioSession().configure()
        XCTAssertTrue(rtcAudioSession.useManualAudio)
        XCTAssertFalse(rtcAudioSession.isAudioEnabled)

        CallAudioSession().start()
        XCTAssertTrue(rtcAudioSession.useManualAudio)
        XCTAssertTrue(rtcAudioSession.isAudioEnabled)

        CallAudioSession().stop()
        XCTAssertTrue(rtcAudioSession.useManualAudio)
        XCTAssertFalse(rtcAudioSession.isAudioEnabled)
    }
}
