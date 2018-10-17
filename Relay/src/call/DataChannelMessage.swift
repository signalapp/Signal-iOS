//  Created by Michael Kirk on 12/8/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation

class DataChannelMessage {

    private let connected: Connected?
    private let hangup: Hangup?
    private let videoStreamingStatus: VideoStreamingStatus?

    private class Connected {
        let peerId: String

        init(peerId: String) {
            self.peerId = peerId
        }

        func asProtobuf() -> OWSWebRTCProtosConnected {
            // TODO: Replace with control message handling
//            let builder = OWSWebRTCProtosConnectedBuilder()
//            builder.setId(callId)
//            return builder.build()
            return OWSWebRTCProtosConnected()
        }
    }

    private class Hangup {
        let peerId: String

        init(peerId: String) {
            self.peerId = peerId
        }

        func asProtobuf() -> OWSWebRTCProtosHangup {
            // TODO: Convert to control message handler
//            let builder = OWSWebRTCProtosHangupBuilder()
//            builder.setId(callId)
//            return builder.build()
            return OWSWebRTCProtosHangup()
        }
    }

    private class VideoStreamingStatus {
        private let peerId: String
        private let enabled: Bool

        init(peerId: String, enabled: Bool) {
            self.peerId = peerId
            self.enabled = enabled
        }

        func asProtobuf() -> OWSWebRTCProtosVideoStreamingStatus {
            // TODO: Convert to control message handling
//            let builder = OWSWebRTCProtosVideoStreamingStatusBuilder()
//            builder.setId(peerId)
//            builder.setEnabled(enabled)
//            return builder.build()
            return OWSWebRTCProtosVideoStreamingStatus()
        }
    }

    // MARK: Init

    private init(connected: Connected) {
        self.connected = connected
        self.hangup = nil
        self.videoStreamingStatus = nil
    }

    private init(hangup: Hangup) {
        self.connected = nil
        self.hangup = hangup
        self.videoStreamingStatus = nil
    }

    private init(videoStreamingStatus: VideoStreamingStatus) {
        self.connected = nil
        self.hangup = nil
        self.videoStreamingStatus = videoStreamingStatus
    }

    // MARK: Factory

    class func forConnected(peerId: String) -> DataChannelMessage {
        return DataChannelMessage(connected:Connected(peerId: peerId))
    }

    class func forHangup(peerId: String) -> DataChannelMessage {
        return DataChannelMessage(hangup: Hangup(peerId: peerId))
    }

    class func forVideoStreamingStatus(peerId: String, enabled: Bool) -> DataChannelMessage {
        return DataChannelMessage(videoStreamingStatus: VideoStreamingStatus(peerId: peerId, enabled: enabled))
    }

    // MARK: Serialization

    func asProtobuf() -> PBGeneratedMessage {
        let builder = OWSWebRTCProtosDataBuilder()
        if connected != nil {
            builder.setConnected(connected!.asProtobuf())
        }

        if hangup != nil {
            builder.setHangup(hangup!.asProtobuf())
        }

        if videoStreamingStatus != nil {
            builder.setVideoStreamingStatus(videoStreamingStatus!.asProtobuf())
        }

        return builder.build()
    }

    func asData() -> Data {
        return self.asProtobuf().data()
    }
}
