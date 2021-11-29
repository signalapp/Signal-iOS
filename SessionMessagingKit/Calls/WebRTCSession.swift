import PromiseKit
import WebRTC

public protocol WebRTCSessionDelegate : AnyObject {
    var videoCapturer: RTCVideoCapturer { get }
    
    func webRTCIsConnected()
    func isRemoteVideoDidChange(isEnabled: Bool)
    func dataChannelDidOpen()
    func didReceiveHangUpSignal()
}

/// See https://webrtc.org/getting-started/overview for more information.
public final class WebRTCSession : NSObject, RTCPeerConnectionDelegate {
    public weak var delegate: WebRTCSessionDelegate?
    public let uuid: String
    private let contactSessionID: String
    private var queuedICECandidates: [RTCIceCandidate] = []
    private var iceCandidateSendTimer: Timer?
    
    private lazy var defaultICEServer: TurnServerInfo? = {
        let url = Bundle.main.url(forResource: "Session-Turn-Server", withExtension: nil)!
        let data = try! Data(contentsOf: url)
        let json = try! JSONSerialization.jsonObject(with: data, options: [ .fragmentsAllowed ]) as! JSON
        return TurnServerInfo(attributes: json)
    }()
    
    internal lazy var factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    /// Represents a WebRTC connection between the user and a remote peer. Provides methods to connect to a
    /// remote peer, maintain and monitor the connection, and close the connection once it's no longer needed.
    internal lazy var peerConnection: RTCPeerConnection = {
        let configuration = RTCConfiguration()
        configuration.iceServers = [ RTCIceServer(urlStrings: ["stun:freyr.getsession.org:5349"]), RTCIceServer(urlStrings: ["turn:freyr.getsession.org"], username: "session", credential: "session") ]
        if let defaultICEServer = defaultICEServer {
            configuration.iceServers.append(RTCIceServer(urlStrings: defaultICEServer.urls, username: defaultICEServer.username, credential: defaultICEServer.password))
        }
        configuration.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: [:], optionalConstraints: [:])
        return factory.peerConnection(with: configuration, constraints: constraints, delegate: self)
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
        let result = factory.videoSource()
        result.adaptOutputFormat(toWidth: 360, height: 780, fps: 30)
        return result
    }()
    
    internal lazy var localVideoTrack: RTCVideoTrack = {
        return factory.videoTrack(with: localVideoSource, trackId: "ARDAMSv0")
    }()
    
    internal lazy var remoteVideoTrack: RTCVideoTrack? = {
        return peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
    }()
    
    // Data Channel
    internal var dataChannel: RTCDataChannel?
    
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
    public static var current: WebRTCSession?
    
    public init(for contactSessionID: String, with uuid: String) {
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        self.contactSessionID = contactSessionID
        self.uuid = uuid
        super.init()
        let mediaStreamTrackIDS = ["ARDAMS"]
        peerConnection.add(audioTrack, streamIds: mediaStreamTrackIDS)
        peerConnection.add(localVideoTrack, streamIds: mediaStreamTrackIDS)
        // Configure audio session
        configureAudioSession()
        
        // Data channel
        if let dataChannel = createDataChannel() {
            dataChannel.delegate = self
            self.dataChannel = dataChannel
        }
        
        // Network reachability
        NotificationCenter.default.addObserver(forName: .reachabilityChanged, object: nil, queue: nil) { _ in
            print("[Calls] Reachability did change.")
            if self.peerConnection.signalingState == .stable {
                Storage.write { transaction in
                    self.sendOffer(to: self.contactSessionID, using: transaction, isRestartingICEConnection: true).retainUntilComplete()
                }
            }
        }
    }
    
    // MARK: Signaling
    public func sendPreOffer(to sessionID: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<String?> {
        print("[Calls] Sending pre-offer message.")
        guard let thread = TSContactThread.fetch(for: sessionID, using: transaction) else { return Promise(error: Error.noThread) }
        let (promise, seal) = Promise<String?>.pending()
        DispatchQueue.main.async {
            let message = CallMessage()
            message.sender = getUserHexEncodedPublicKey()
            message.sentTimestamp = NSDate.millisecondTimestamp()
            message.uuid = self.uuid
            message.kind = .preOffer
            let infoMessage = TSInfoMessage.from(message, associatedWith: thread)
            infoMessage.save(with: transaction)
            MessageSender.sendNonDurably(message, in: thread, using: transaction).done2 {
                print("[Calls] Pre-offer message has been sent.")
                seal.fulfill((infoMessage.uniqueId))
            }.catch2 { error in
                seal.reject(error)
            }
        }
        return promise
    }
    
    public func sendOffer(to sessionID: String, using transaction: YapDatabaseReadWriteTransaction, isRestartingICEConnection: Bool = false) -> Promise<Void> {
        print("[Calls] Sending offer message.")
        guard let thread = TSContactThread.fetch(for: sessionID, using: transaction) else { return Promise(error: Error.noThread) }
        let (promise, seal) = Promise<Void>.pending()
        peerConnection.offer(for: mediaConstraints(isRestartingICEConnection)) { [weak self] sdp, error in
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
                    message.sentTimestamp = NSDate.millisecondTimestamp()
                    message.uuid = self.uuid
                    message.kind = .offer
                    message.sdps = [ sdp.sdp ]
                    MessageSender.sendNonDurably(message, in: thread, using: transaction).done2 {
                        seal.fulfill(())
                    }.catch2 { error in
                        seal.reject(error)
                    }
                }
            }
        }
        return promise
    }
    
    public func sendAnswer(to sessionID: String, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        print("[Calls] Sending answer message.")
        guard let thread = TSContactThread.fetch(for: sessionID, using: transaction) else { return Promise(error: Error.noThread) }
        let (promise, seal) = Promise<Void>.pending()
        peerConnection.answer(for: mediaConstraints(false)) { [weak self] sdp, error in
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
                    message.uuid = self.uuid
                    message.kind = .answer
                    message.sdps = [ sdp.sdp ]
                    MessageSender.sendNonDurably(message, in: thread, using: transaction).done2 {
                        seal.fulfill(())
                    }.catch2 { error in
                        seal.reject(error)
                    }
                }
            }
        }
        return promise
    }
    
    private func queueICECandidateForSending(_ candidate: RTCIceCandidate) {
        queuedICECandidates.append(candidate)
        DispatchQueue.main.async {
            self.iceCandidateSendTimer?.invalidate()
            self.iceCandidateSendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
                self.sendICECandidates()
            }
        }
    }
    
    private func sendICECandidates() {
        Storage.write { transaction in
            let candidates = self.queuedICECandidates
            guard let thread = TSContactThread.fetch(for: self.contactSessionID, using: transaction) else { return }
            print("[Calls] Batch sending \(candidates.count) ICE candidates.")
            let message = CallMessage()
            let sdps = candidates.map { $0.sdp }
            let sdpMLineIndexes = candidates.map { UInt32($0.sdpMLineIndex) }
            let sdpMids = candidates.map { $0.sdpMid! }
            message.uuid = self.uuid
            message.kind = .iceCandidates(sdpMLineIndexes: sdpMLineIndexes, sdpMids: sdpMids)
            message.sdps = sdps
            self.queuedICECandidates.removeAll()
            MessageSender.sendNonDurably(message, in: thread, using: transaction).retainUntilComplete()
        }
    }
    
    public func endCall(with sessionID: String, using transaction: YapDatabaseReadWriteTransaction) {
        guard let thread = TSContactThread.fetch(for: sessionID, using: transaction) else { return }
        let message = CallMessage()
        message.uuid = self.uuid
        message.kind = .endCall
        print("[Calls] Sending end call message.")
        MessageSender.sendNonDurably(message, in: thread, using: transaction).retainUntilComplete()
    }
    
    public func dropConnection() {
        peerConnection.close()
    }
    
    private func mediaConstraints(_ isRestartingICEConnection: Bool) -> RTCMediaConstraints {
        var mandatory: [String:String] = [
            kRTCMediaConstraintsOfferToReceiveAudio : kRTCMediaConstraintsValueTrue,
            kRTCMediaConstraintsOfferToReceiveVideo : kRTCMediaConstraintsValueTrue,
        ]
        if isRestartingICEConnection { mandatory[kRTCMediaConstraintsIceRestart] = kRTCMediaConstraintsValueTrue }
        let optional: [String:String] = [:]
        return RTCMediaConstraints(mandatoryConstraints: mandatory, optionalConstraints: optional)
    }
    
    // MARK: Peer connection delegate
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        print("[Calls] Signaling state changed to: \(state).")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("[Calls] Peer connection did add stream.")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("[Calls] Peer connection did remove stream.")
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("[Calls] Peer connection should negotiate.")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceConnectionState) {
        print("[Calls] ICE connection state changed to: \(state).")
        if state == .connected {
            delegate?.webRTCIsConnected()
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceGatheringState) {
        print("[Calls] ICE gathering state changed to: \(state).")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        queueICECandidateForSending(candidate)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("[Calls] \(candidates.count) ICE candidate(s) removed.")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("[Calls] Data channel opened.")
    }
}

extension WebRTCSession {
    public func configureAudioSession(outputAudioPort: AVAudioSession.PortOverride = .none) {
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.lockForConfiguration()
        do {
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord.rawValue)
            try audioSession.setMode(AVAudioSession.Mode.voiceChat.rawValue)
            try audioSession.overrideOutputAudioPort(outputAudioPort)
            try audioSession.setActive(true)
        } catch let error {
            SNLog("Couldn't set up WebRTC audio session due to error: \(error)")
        }
        audioSession.unlockForConfiguration()
    }
    
    public func audioSessionDidActivate(_ audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
        configureAudioSession()
    }
    
    public func audioSessionDidDeactivate(_ audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }
    
    public func mute() {
        audioTrack.isEnabled = false
    }
    
    public func unmute() {
        audioTrack.isEnabled = true
    }
    
    public func turnOffVideo() {
        localVideoTrack.isEnabled = false
        sendJSON(["video": false])
    }
    
    public func turnOnVideo() {
        localVideoTrack.isEnabled = true
        sendJSON(["video": true])
    }
    
    public func hangUp() {
        sendJSON(["hangup": true])
    }
}
