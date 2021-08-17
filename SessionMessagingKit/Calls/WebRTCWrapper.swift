import PromiseKit
import WebRTC

public protocol WebRTCWrapperDelegate : AnyObject {
    var videoCapturer: RTCVideoCapturer { get }

    func sendSDP(_ sdp: RTCSessionDescription)
    func sendICECandidate(_ candidate: RTCIceCandidate)
}

/// See https://webrtc.org/getting-started/overview for more information.
public final class WebRTCWrapper : NSObject, RTCPeerConnectionDelegate {
    public weak var delegate: WebRTCWrapperDelegate?
    internal var candidateQueue: [RTCIceCandidate] = []
    
    internal lazy var factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCVideoEncoderFactoryH264()
        let videoDecoderFactory = RTCVideoDecoderFactoryH264()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    /// Represents a WebRTC connection between the user and a remote peer. Provides methods to connect to a
    /// remote peer, maintain and monitor the connection, and close the connection once it's no longer needed.
    internal lazy var peerConnection: RTCPeerConnection = {
        let configuration = RTCConfiguration()
        configuration.iceServers = [ RTCIceServer(urlStrings: TestCallConfig.defaultICEServers) ]
        configuration.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: [:], optionalConstraints: [:])
        return factory.peerConnection(with: configuration, constraints: constraints, delegate: self)
    }()
    
    internal lazy var mediaConstraints: RTCMediaConstraints = {
        let mandatory: [String:String] = [
            kRTCMediaConstraintsOfferToReceiveAudio : kRTCMediaConstraintsValueTrue,
            kRTCMediaConstraintsOfferToReceiveVideo : kRTCMediaConstraintsValueTrue
        ]
        let optional: [String:String] = [:]
        return RTCMediaConstraints(mandatoryConstraints: mandatory, optionalConstraints: optional)
    }()
    
    // Audio
    internal lazy var audioSource: RTCAudioSource = {
        let constraints = RTCMediaConstraints(mandatoryConstraints: [:], optionalConstraints: [:])
        return factory.audioSource(with: constraints)
    }()
    
    internal lazy var audioTrack: RTCAudioTrack = {
        return factory.audioTrack(with: audioSource, trackId: "ARDAMSa0")
    }()
    
    // Video
    public lazy var localVideoSource: RTCVideoSource = {
        return factory.videoSource()
    }()
    
    internal lazy var localVideoTrack: RTCVideoTrack = {
        return factory.videoTrack(with: localVideoSource, trackId: "ARDAMSv0")
    }()
    
    internal lazy var remoteVideoTrack: RTCVideoTrack? = {
        return peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
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
    public override init() {
        super.init()
        let mediaStreamTrackIDS = ["ARDAMS"]
        peerConnection.add(audioTrack, streamIds: mediaStreamTrackIDS)
        peerConnection.add(localVideoTrack, streamIds: mediaStreamTrackIDS)
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
    
    // MARK: General
    public func drainICECandidateQueue() {
        print("[Calls] Draining ICE candidate queue.")
        candidateQueue.forEach { peerConnection.add($0) }
        candidateQueue.removeAll()
    }
    
    // MARK: Call Management
    public func offer() -> Promise<Void> {
        print("[Calls] Initiating call.")
        /*
        guard let thread = TSContactThread.fetch(for: publicKey, using: transaction) else { return Promise(error: Error.noThread) }
         */
        let (promise, seal) = Promise<Void>.pending()
        peerConnection.offer(for: mediaConstraints) { [weak self] sdp, error in
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
                
                self.delegate?.sendSDP(sdp)
                
                /*
                let message = CallMessage()
                message.type = .offer
                message.sdp = sdp.sdp
                MessageSender.send(message, in: thread, using: transaction)
                 */
                seal.fulfill(())
            }
        }
        return promise
    }
    
    public func answer() -> Promise<Void> {
        print("[Calls] Accepting call.")
        /*
        guard let thread = TSContactThread.fetch(for: publicKey, using: transaction) else { return Promise(error: Error.noThread) }
         */
        let (promise, seal) = Promise<Void>.pending()
        peerConnection.answer(for: mediaConstraints) { [weak self] sdp, error in
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
                
                self.delegate?.sendSDP(sdp)
                
                /*
                let message = CallMessage()
                message.type = .answer
                message.sdp = sdp.sdp
                MessageSender.send(message, in: thread, using: transaction)
                 */
                seal.fulfill(())
            }
        }
        return promise
    }
    
    public func dropConnection() {
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
        delegate?.sendICECandidate(candidate)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        SNLog("\(candidates.count) ICE candidate(s) removed.")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        SNLog("Data channel opened.")
    }
}
