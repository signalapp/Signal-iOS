import PromiseKit
import WebRTC

/// See https://developer.mozilla.org/en-US/docs/Web/API/RTCSessionDescription for more information.
public final class CallManager : NSObject, RTCPeerConnectionDelegate {
    
    private lazy var factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCVideoEncoderFactoryH264()
        let videoDecoderFactory = RTCVideoDecoderFactoryH264()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    /// Represents a WebRTC connection between the user and a remote peer. Provides methods to connect to a
    /// remote peer, maintain and monitor the connection, and close the connection once it's no longer needed.
    private lazy var peerConnection: RTCPeerConnection = {
        let configuration = RTCConfiguration()
        // TODO: Configure
        // TODO: Do these constraints make sense?
        let constraints = RTCMediaConstraints(mandatoryConstraints: [:], optionalConstraints: [ "DtlsSrtpKeyAgreement" : "true" ])
        return factory.peerConnection(with: configuration, constraints: constraints, delegate: self)
    }()
    
    private lazy var constraints: RTCMediaConstraints = {
        let mandatory: [String:String] = [
            kRTCMediaConstraintsOfferToReceiveAudio : kRTCMediaConstraintsValueTrue,
            kRTCMediaConstraintsOfferToReceiveVideo : kRTCMediaConstraintsValueTrue
        ]
        let optional: [String:String] = [:]
        // TODO: Do these constraints make sense?
        return RTCMediaConstraints(mandatoryConstraints: mandatory, optionalConstraints: optional)
    }()
    
    // Audio
    private lazy var audioSource: RTCAudioSource = {
        // TODO: Do these constraints make sense?
        let constraints = RTCMediaConstraints(mandatoryConstraints: [:], optionalConstraints: [:])
        return factory.audioSource(with: constraints)
    }()
    
    private lazy var audioTrack: RTCAudioTrack = {
        return factory.audioTrack(with: audioSource, trackId: "ARDAMSa0")
    }()
    
    // Video
    private lazy var localVideoSource: RTCVideoSource = {
        return factory.videoSource()
    }()
    
    private lazy var localVideoTrack: RTCVideoTrack = {
        return factory.videoTrack(with: localVideoSource, trackId: "ARDAMSv0")
    }()
    
    private lazy var videoCapturer: RTCVideoCapturer = {
        return RTCCameraVideoCapturer(delegate: localVideoSource)
    }()
    
    private lazy var remoteVideoTrack: RTCVideoTrack? = {
        return peerConnection.receivers.first { $0.track.kind == "video" }?.track as? RTCVideoTrack
    }()
    
    // Stream
    private lazy var stream: RTCMediaStream = {
        let result = factory.mediaStream(withStreamId: "ARDAMS")
        result.addAudioTrack(audioTrack)
        result.addVideoTrack(localVideoTrack)
        return result
    }()
    
    // MARK: Error
    public enum Error : LocalizedError {
        case noThread
        
        public var errorDescription: String? {
            switch self {
            case .noThread: return "Couldn't find thread for contact."
            }
        }
    }
    
    // MARK: Initialization
    private override init() {
        super.init()
        peerConnection.add(stream)
        // Configure audio session
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.lockForConfiguration()
        do {
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord.rawValue)
            try audioSession.setMode(AVAudioSession.Mode.voiceChat.rawValue)
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true)
        } catch let error {
            SNLog("Couldn't set up WebRTC audio session due to error: \(error)")
        }
        audioSession.unlockForConfiguration()
    }
    
    public static let shared = CallManager()
    
    // MARK: Call Management
    public func initiateCall(with publicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        guard let thread = TSContactThread.fetch(for: publicKey, using: transaction) else { return Promise(error: Error.noThread) }
        let (promise, seal) = Promise<Void>.pending()
        peerConnection.offer(for: constraints) { [weak self] sdp, error in
            if let error = error {
                seal.reject(error)
            } else {
                guard let self = self, let sdp = sdp else { preconditionFailure() }
                self.peerConnection.setLocalDescription(sdp) { error in
                    if let error = error {
                        print("Couldn't initiate call due to error: \(error).")
                        return seal.reject(error)
                    }
                }
                let message = CallMessage()
                message.type = .offer
                message.sdp = sdp.sdp
                MessageSender.send(message, in: thread, using: transaction)
                seal.fulfill(())
            }
        }
        return promise
    }
    
    public func acceptCall(with publicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        guard let thread = TSContactThread.fetch(for: publicKey, using: transaction) else { return Promise(error: Error.noThread) }
        let (promise, seal) = Promise<Void>.pending()
        peerConnection.answer(for: constraints) { [weak self] sdp, error in
            if let error = error {
                seal.reject(error)
            } else {
                guard let self = self, let sdp = sdp else { preconditionFailure() }
                self.peerConnection.setLocalDescription(sdp) { error in
                    if let error = error {
                        print("Couldn't accept call due to error: \(error).")
                        return seal.reject(error)
                    }
                }
                let message = CallMessage()
                message.type = .answer
                message.sdp = sdp.sdp
                MessageSender.send(message, in: thread, using: transaction)
                seal.fulfill(())
            }
        }
        return promise
    }
    
    public func endCall() {
        peerConnection.close()
    }
    
    // MARK: Delegate
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        SNLog("Signaling state changed to: \(state).")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        // Do nothing
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        // Do nothing
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // Do nothing
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceConnectionState) {
        SNLog("ICE connection state changed to: \(state).")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceGatheringState) {
        SNLog("ICE gathering state changed to: \(state).")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        SNLog("ICE candidate generated.")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        SNLog("\(candidates.count) ICE candidate(s) removed.")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        SNLog("Data channel opened.")
    }
}
