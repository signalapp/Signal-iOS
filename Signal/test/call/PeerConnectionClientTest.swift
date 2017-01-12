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

    internal func peerConnectionClientIceConnected(_ peerconnectionClient: PeerConnectionClient) {
        connectionState = .connected
    }

    internal func peerConnectionClientIceFailed(_ peerconnectionClient: PeerConnectionClient) {
        connectionState = .failed
    }

    internal func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, addedLocalIceCandidate iceCandidate: RTCIceCandidate) {
        localIceCandidates.append(iceCandidate)
    }
}

class PeerConnectionClientTest: XCTestCase {

    var client: PeerConnectionClient!
    var clientDelegate: FakePeerConnectionClientDelegate!
    var peerConnection: RTCPeerConnection!

    override func setUp() {
        super.setUp()

        let iceServers = [RTCIceServer]()
        clientDelegate = FakePeerConnectionClientDelegate()
        client = PeerConnectionClient(iceServers: iceServers, delegate: clientDelegate)
        peerConnection = client.peerConnection
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

}
