//  Created by Michael Kirk on 1/11/17.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.

import XCTest
import WebRTC

/**
 * Playing the role of the call service.
 */
class FakePeerConnectionClientDelegate: PeerConnectionClientDelegate {

    enum ConnectionState {
        case connected, failed
    }

    var connectionState: ConnectionState?
    var localIceCandidates = [RTCIceCandidate]()
    var dataChannelMessages = [OWSWebRTCProtosData]()

    internal func peerConnectionClientIceConnected(_ peerconnectionClient: PeerConnectionClient) {
        connectionState = .connected
    }

    internal func peerConnectionClientIceFailed(_ peerconnectionClient: PeerConnectionClient) {
        connectionState = .failed
    }

    internal func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, addedLocalIceCandidate iceCandidate: RTCIceCandidate) {
        localIceCandidates.append(iceCandidate)
    }

    internal func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, received dataChannelMessage: OWSWebRTCProtosData) {
        dataChannelMessages.append(dataChannelMessage)
    }
}

class PeerConnectionClientTest: XCTestCase {

    var client: PeerConnectionClient!
    var clientDelegate: FakePeerConnectionClientDelegate!
    var peerConnection: RTCPeerConnection!
    var dataChannel: RTCDataChannel!

    override func setUp() {
        super.setUp()

        let iceServers = [RTCIceServer]()
        clientDelegate = FakePeerConnectionClientDelegate()
        client = PeerConnectionClient(iceServers: iceServers, delegate: clientDelegate)
        peerConnection = client.peerConnection
        client.createSignalingDataChannel()
        dataChannel = client.dataChannel!
    }

    override func tearDown() {
        client.terminate()

        super.tearDown()
    }

    func testIceConnectionStateChange() {
        XCTAssertNil(clientDelegate.connectionState)

        client.peerConnection(peerConnection, didChange: RTCIceConnectionState.connected)
        XCTAssertEqual(FakePeerConnectionClientDelegate.ConnectionState.connected, clientDelegate.connectionState)

        client.peerConnection(peerConnection, didChange: RTCIceConnectionState.completed)
        XCTAssertEqual(FakePeerConnectionClientDelegate.ConnectionState.connected, clientDelegate.connectionState)

        client.peerConnection(peerConnection, didChange: RTCIceConnectionState.failed)
        XCTAssertEqual(FakePeerConnectionClientDelegate.ConnectionState.failed, clientDelegate.connectionState)
    }

    func testIceCandidateAdded() {
        XCTAssertEqual(0, clientDelegate.localIceCandidates.count)

        let candidate1 = RTCIceCandidate(sdp: "sdp-1", sdpMLineIndex: 0, sdpMid: "sdpMid-1")
        let candidate2 = RTCIceCandidate(sdp: "sdp-2", sdpMLineIndex: 0, sdpMid: "sdpMid-2")
        let candidate3 = RTCIceCandidate(sdp: "sdp-3", sdpMLineIndex: 0, sdpMid: "sdpMid-3")

        client.peerConnection(peerConnection, didGenerate: candidate1)
        client.peerConnection(peerConnection, didGenerate: candidate2)
        client.peerConnection(peerConnection, didGenerate: candidate3)

        XCTAssertEqual(3, clientDelegate.localIceCandidates.count)
    }

    func testDataChannelMessage() {
        XCTAssertEqual(0, clientDelegate.dataChannelMessages.count)

        let hangup = DataChannelMessage.forHangup(callId: 123)
        let hangupBuffer = RTCDataBuffer(data: hangup.asData(), isBinary: false)
        client.dataChannel(dataChannel, didReceiveMessageWith: hangupBuffer)

        XCTAssertEqual(1, clientDelegate.dataChannelMessages.count)

        let dataChannelMessageProto = clientDelegate.dataChannelMessages[0]
        XCTAssert(dataChannelMessageProto.hasHangup())

        let hangupProto = dataChannelMessageProto.hangup!
        XCTAssertEqual(123, hangupProto.id)
    }
}
