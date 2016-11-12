//  Created by Michael Kirk on 12/8/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation

class DataChannelMessage {

    private let connected: Connected?
    private let hangup: Hangup?
    private let videoStreamingStatus: VideoStreamingStatus?

    private class Connected {
        let callId: UInt64

        init(callId: UInt64) {
            self.callId = callId
        }

        func asProtobuf() -> OWSWebRTCProtosConnected {
            let builder = OWSWebRTCProtosConnectedBuilder()
            builder.setId(callId)
            return builder.build()
        }
    }

    private class Hangup {
        let callId: UInt64

        init(callId: UInt64) {
            self.callId = callId
        }

        func asProtobuf() -> OWSWebRTCProtosHangup {
            let builder = OWSWebRTCProtosHangupBuilder()
            builder.setId(callId)
            return builder.build()
        }
    }

    private class VideoStreamingStatus {
        private let callId: UInt64
        private let enabled: Bool

        init(callId: UInt64, enabled: Bool) {
            self.callId = callId
            self.enabled = enabled
        }

        func asProtobuf() -> OWSWebRTCProtosVideoStreamingStatus {
            let builder = OWSWebRTCProtosVideoStreamingStatusBuilder()
            builder.setId(callId)
            builder.setEnabled(enabled)
            return builder.build()
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

    class func forConnected(callId: UInt64) -> DataChannelMessage {
        return DataChannelMessage(connected:Connected(callId: callId))
    }

    class func forHangup(callId: UInt64) -> DataChannelMessage {
        return DataChannelMessage(hangup: Hangup(callId: callId))
    }

    class func forVideoStreamingStatus(callId: UInt64, enabled: Bool) -> DataChannelMessage {
        return DataChannelMessage(videoStreamingStatus: VideoStreamingStatus(callId: callId, enabled: enabled))
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
