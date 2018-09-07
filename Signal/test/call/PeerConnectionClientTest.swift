//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
import WebRTC
@testable import Signal

/**
 * Playing the role of the call service.
 */
class FakePeerConnectionClientDelegate: PeerConnectionClientDelegate {

    enum ConnectionState {
        case connected, disconnected, failed
    }

    var connectionState: ConnectionState?
    var localIceCandidates = [RTCIceCandidate]()
    var dataChannelMessages = [WebRTCProtoData]()

    func peerConnectionClientIceConnected(_ peerconnectionClient: PeerConnectionClient) {
        connectionState = .connected
    }

    func peerConnectionClientIceDisconnected(_ peerconnectionClient: PeerConnectionClient) {
        connectionState = .disconnected
    }

    func peerConnectionClientIceFailed(_ peerconnectionClient: PeerConnectionClient) {
        connectionState = .failed
    }

    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, addedLocalIceCandidate iceCandidate: RTCIceCandidate) {
        localIceCandidates.append(iceCandidate)
    }

    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, received dataChannelMessage: WebRTCProtoData) {
        dataChannelMessages.append(dataChannelMessage)
    }

    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateLocalVideoCaptureSession captureSession: AVCaptureSession?) {
    }

    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateRemoteVideoTrack videoTrack: RTCVideoTrack?) {
    }
}

class PeerConnectionClientTest: SignalBaseTest {

    var client: PeerConnectionClient!
    var clientDelegate: FakePeerConnectionClientDelegate!
    var peerConnection: RTCPeerConnection!
    var dataChannel: RTCDataChannel!

    override func setUp() {
        super.setUp()

        let iceServers = [RTCIceServer]()
        clientDelegate = FakePeerConnectionClientDelegate()
        client = PeerConnectionClient(iceServers: iceServers, delegate: clientDelegate, callDirection: .outgoing, useTurnOnly: false)
        peerConnection = client.peerConnectionForTests()
        dataChannel = client.dataChannelForTests()
    }

    override func tearDown() {
        client.terminate()

        super.tearDown()
    }

    func testIceConnectionStateChange() {
        XCTAssertNil(clientDelegate.connectionState)

        client.peerConnection(peerConnection, didChange: RTCIceConnectionState.connected)
        waitForPeerConnectionClient()
        XCTAssertEqual(FakePeerConnectionClientDelegate.ConnectionState.connected, clientDelegate.connectionState)

        client.peerConnection(peerConnection, didChange: RTCIceConnectionState.completed)
        waitForPeerConnectionClient()
        XCTAssertEqual(FakePeerConnectionClientDelegate.ConnectionState.connected, clientDelegate.connectionState)

        client.peerConnection(peerConnection, didChange: RTCIceConnectionState.failed)
        waitForPeerConnectionClient()
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

        waitForPeerConnectionClient()

        XCTAssertEqual(3, clientDelegate.localIceCandidates.count)
    }

    func waitForPeerConnectionClient() {
        // PeerConnectionClient processes RTCPeerConnectionDelegate invocations first on the signaling queue...
        client.flushSignalingQueueForTests()
        // ...then on the main queue.
        let expectation = self.expectation(description: "Wait for PeerConnectionClient to call delegate method on main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        self.waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testDataChannelMessage() {
        XCTAssertEqual(0, clientDelegate.dataChannelMessages.count)

        let hangupBuilder = WebRTCProtoHangup.WebRTCProtoHangupBuilder()
        hangupBuilder.setId(123)
        let hangup = try! hangupBuilder.build()

        let dataBuilder = WebRTCProtoData.WebRTCProtoDataBuilder()
        dataBuilder.setHangup(hangup)
        let hangupData = try! dataBuilder.buildSerializedData()
        let hangupBuffer = RTCDataBuffer(data: hangupData, isBinary: false)
        client.dataChannel(dataChannel, didReceiveMessageWith: hangupBuffer)

        waitForPeerConnectionClient()

        XCTAssertEqual(1, clientDelegate.dataChannelMessages.count)

        let dataChannelMessageProto = clientDelegate.dataChannelMessages[0]
        XCTAssertNotNil(dataChannelMessageProto.hangup)

        let hangupProto = dataChannelMessageProto.hangup!
        XCTAssertEqual(123, hangupProto.id)
    }
}
