import PromiseKit
import WebRTC

public protocol WebRTCWrapperDelegate : AnyObject {
    var videoCapturer: RTCVideoCapturer { get }
}

/// See https://webrtc.org/getting-started/overview for more information.
public final class WebRTCWrapper : NSObject, RTCPeerConnectionDelegate {
    public weak var delegate: WebRTCWrapperDelegate?
    private let contactSessionID: String
    private var queuedICECandidates: [RTCIceCandidate] = []
    private var iceCandidateSendTimer: Timer?
    
    private let defaultICEServers = [
        "stun:stun.l.google.com:19302",
        "stun:stun1.l.google.com:19302",
        "stun:stun2.l.google.com:19302",
        "stun:stun3.l.google.com:19302",
        "stun:stun4.l.google.com:19302"
    ]
    
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
        configuration.iceServers = [ RTCIceServer(urlStrings: defaultICEServers) ]
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
    public static var current: WebRTCWrapper?
    
    public init(for contactSessionID: String) {
        self.contactSessionID = contactSessionID
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
    
    // MARK: Signaling
    public func sendOffer(to sessionID: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        print("[Calls] Initiating call.")
        guard let thread = TSContactThread.fetch(for: sessionID, using: transaction) else { return Promise(error: Error.noThread) }
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
                DispatchQueue.main.async {
                    let message = CallMessage()
                    message.kind = .offer
                    message.sdps = [ sdp.sdp ]
                    MessageSender.send(message, in: thread, using: transaction)
                    seal.fulfill(())
                }
            }
        }
        return promise
    }
    
    public func sendAnswer(to sessionID: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        print("[Calls] Accepting call.")
        guard let thread = TSContactThread.fetch(for: sessionID, using: transaction) else { return Promise(error: Error.noThread) }
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
                DispatchQueue.main.async {
                    let message = CallMessage()
                    message.kind = .answer
                    message.sdps = [ sdp.sdp ]
                    MessageSender.send(message, in: thread, using: transaction)
                    seal.fulfill(())
                }
            }
        }
        return promise
    }
    
    private func queueICECandidateForSending(_ candidate: RTCIceCandidate) {
        queuedICECandidates.append(candidate)
        iceCandidateSendTimer?.invalidate()
        iceCandidateSendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
            self.sendICECandidates()
        }
    }
    
    private func sendICECandidates() {
        Storage.write { transaction in
            let candidates = self.queuedICECandidates
            guard let thread = TSContactThread.fetch(for: self.contactSessionID, using: transaction) else { return }
            let message = CallMessage()
            let sdps = candidates.map { $0.sdp }
            let sdpMLineIndexes = candidates.map { UInt32($0.sdpMLineIndex) }
            let sdpMids = candidates.map { $0.sdpMid! }
            message.kind = .iceCandidates(sdpMLineIndexes: sdpMLineIndexes, sdpMids: sdpMids)
            message.sdps = sdps
            self.queuedICECandidates.removeAll()
            MessageSender.send(message, in: thread, using: transaction)
        }
    }
    
    public func dropConnection() {
        peerConnection.close()
    }
    
    // MARK: Delegate
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        print("[Calls] Signaling state changed to: \(state).")
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
        print("[Calls] ICE connection state changed to: \(state).")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceGatheringState) {
        print("[Calls] ICE gathering state changed to: \(state).")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("[Calls] ICE candidate generated.")
        queueICECandidateForSending(candidate)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("[Calls] \(candidates.count) ICE candidate(s) removed.")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("[Calls] Data channel opened.")
    }
}
