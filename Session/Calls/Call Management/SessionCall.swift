import Foundation
import WebRTC
import SessionMessagingKit
import PromiseKit
import CallKit

public final class SessionCall: NSObject, WebRTCSessionDelegate {
    // MARK: Metadata Properties
    let uuid: String
    let callID: UUID // This is for CallKit
    let sessionID: String
    let mode: Mode
    let webRTCSession: WebRTCSession
    let isOutgoing: Bool
    var remoteSDP: RTCSessionDescription? = nil
    var callMessageTimestamp: UInt64?
    var answerCallAction: CXAnswerCallAction? = nil
    var contactName: String {
        let contact = Storage.shared.getContact(with: self.sessionID)
        return contact?.displayName(for: Contact.Context.regular) ?? self.sessionID
    }
    var profilePicture: UIImage {
        if let result = OWSProfileManager.shared().profileAvatar(forRecipientId: sessionID) {
            return result
        } else {
            return Identicon.generatePlaceholderIcon(seed: sessionID, text: contactName, size: 300)
        }
    }
    
    // MARK: Control
    lazy public var videoCapturer: RTCVideoCapturer = {
        return RTCCameraVideoCapturer(delegate: webRTCSession.localVideoSource)
    }()
    
    var isRemoteVideoEnabled = false {
        didSet {
            remoteVideoStateDidChange?(isRemoteVideoEnabled)
        }
    }
    
    var isMuted = false {
        willSet {
            if newValue {
                webRTCSession.mute()
            } else {
                webRTCSession.unmute()
            }
        }
    }
    var isVideoEnabled = false {
        willSet {
            if newValue {
                webRTCSession.turnOnVideo()
            } else {
                webRTCSession.turnOffVideo()
            }
        }
    }
    
    // MARK: Mode
    enum Mode {
        case offer
        case answer
    }
    
    // MARK: End call mode
    enum EndCallMode {
        case local
        case remote
        case unanswered
    }
    
    // MARK: Call State Properties
    var connectingDate: Date? {
        didSet {
            stateDidChange?()
            hasStartedConnectingDidChange?()
        }
    }

    var connectedDate: Date? {
        didSet {
            stateDidChange?()
            hasConnectedDidChange?()
        }
    }

    var endDate: Date? {
        didSet {
            stateDidChange?()
            hasEndedDidChange?()
        }
    }

    // Not yet implemented
    var isOnHold = false {
        didSet {
            stateDidChange?()
        }
    }

    // MARK: State Change Callbacks
    var stateDidChange: (() -> Void)?
    var hasStartedConnectingDidChange: (() -> Void)?
    var hasConnectedDidChange: (() -> Void)?
    var hasEndedDidChange: (() -> Void)?
    var remoteVideoStateDidChange: ((Bool) -> Void)?
    
    // MARK: Derived Properties
    var hasStartedConnecting: Bool {
        get { return connectingDate != nil }
        set { connectingDate = newValue ? Date() : nil }
    }

    var hasConnected: Bool {
        get { return connectedDate != nil }
        set { connectedDate = newValue ? Date() : nil }
    }

    var hasEnded: Bool {
        get { return endDate != nil }
        set { endDate = newValue ? Date() : nil }
    }
    
    var didTimeout = false

    var duration: TimeInterval {
        guard let connectedDate = connectedDate else {
            return 0
        }
        if let endDate = endDate {
            return endDate.timeIntervalSince(connectedDate)
        }

        return Date().timeIntervalSince(connectedDate)
    }
    
    // MARK: Initialization
    init(for sessionID: String, uuid: String, mode: Mode, outgoing: Bool = false) {
        self.sessionID = sessionID
        self.uuid = uuid
        self.callID = UUID()
        self.mode = mode
        self.webRTCSession = WebRTCSession.current ?? WebRTCSession(for: sessionID, with: uuid)
        self.isOutgoing = outgoing
        WebRTCSession.current = self.webRTCSession
        super.init()
        self.webRTCSession.delegate = self
        if AppEnvironment.shared.callManager.currentCall == nil {
            AppEnvironment.shared.callManager.currentCall = self
        } else {
            SNLog("[Calls] A call is ongoing.")
        }
    }
    
    func reportIncomingCallIfNeeded(completion: @escaping (Error?) -> Void) {
        guard case .answer = mode else { return }
        AppEnvironment.shared.callManager.reportIncomingCall(self, callerName: contactName) { error in
            completion(error)
        }
    }
    
    func didReceiveRemoteSDP(sdp: RTCSessionDescription) {
        print("[Calls] Did receive remote sdp.")
        remoteSDP = sdp
        if hasStartedConnecting {
            webRTCSession.handleRemoteSDP(sdp, from: sessionID) // This sends an answer message internally
        }
    }
    
    // MARK: Actions
    func startSessionCall() {
        guard case .offer = mode else { return }
        var promise: Promise<UInt64>!
        Storage.write(with: { transaction in
            promise = self.webRTCSession.sendPreOffer(to: self.sessionID, using: transaction)
        }, completion: { [weak self] in
            let _ = promise.done { timestamp in
                self?.callMessageTimestamp = timestamp
                Storage.shared.write { transaction in
                    self?.webRTCSession.sendOffer(to: self!.sessionID, using: transaction as! YapDatabaseReadWriteTransaction).retainUntilComplete()
                }
            }
        })
    }
    
    func answerSessionCall() {
        guard case .answer = mode else { return }
        hasStartedConnecting = true
        if let sdp = remoteSDP {
            webRTCSession.handleRemoteSDP(sdp, from: sessionID) // This sends an answer message internally
        }
    }
    
    func answerSessionCallInBackground(action: CXAnswerCallAction) {
        answerCallAction = action
        self.answerSessionCall()
    }
    
    func endSessionCall() {
        guard !hasEnded else { return }
        webRTCSession.hangUp()
        Storage.write { transaction in
            self.webRTCSession.endCall(with: self.sessionID, using: transaction)
        }
        hasEnded = true
    }
    
    // MARK: Update call message
    func updateCallMessage(mode: EndCallMode) {
        guard let callMessageTimestamp = callMessageTimestamp else { return }
        Storage.write { transaction in
            let tsMessage: TSMessage?
            if self.isOutgoing {
                tsMessage = TSOutgoingMessage.find(withTimestamp: callMessageTimestamp)
            } else {
                tsMessage = TSIncomingMessage.find(withAuthorId: self.sessionID, timestamp: callMessageTimestamp, transaction: transaction)
            }
            if let messageToUpdate = tsMessage {
                var shouldMarkAsRead = false
                let newMessageBody: String
                if self.duration > 0 {
                    let durationString = NSString.formatDurationSeconds(UInt32(self.duration), useShortFormat: true)
                    newMessageBody = "\(self.isOutgoing ? NSLocalizedString("call_outgoing", comment: "") : NSLocalizedString("call_incoming", comment: "")): \(durationString)"
                    shouldMarkAsRead = true
                } else if self.hasStartedConnecting {
                    newMessageBody = NSLocalizedString("call_cancelled", comment: "")
                    shouldMarkAsRead = true
                } else {
                    switch mode {
                    case .local:
                        newMessageBody = self.isOutgoing ? NSLocalizedString("call_cancelled", comment: "") : NSLocalizedString("call_rejected", comment: "")
                        shouldMarkAsRead = true
                    case .remote:
                        newMessageBody = self.isOutgoing ? NSLocalizedString("call_rejected", comment: "") : NSLocalizedString("call_missing", comment: "")
                    case .unanswered:
                        newMessageBody = NSLocalizedString("call_timeout", comment: "")
                    }
                }
                messageToUpdate.updateCall(withNewBody: newMessageBody, transaction: transaction)
                if let incomingMessage = tsMessage as? TSIncomingMessage, shouldMarkAsRead {
                    incomingMessage.markAsReadNow(withSendReadReceipt: false, transaction: transaction)
                }
            }
        }
    }
    
    // MARK: Renderer
    func attachRemoteVideoRenderer(_ renderer: RTCVideoRenderer) {
        webRTCSession.attachRemoteRenderer(renderer)
    }
    
    func removeRemoteVideoRenderer(_ renderer: RTCVideoRenderer) {
        webRTCSession.removeRemoteRenderer(renderer)
    }
    
    func attachLocalVideoRenderer(_ renderer: RTCVideoRenderer) {
        webRTCSession.attachLocalRenderer(renderer)
    }
    
    // MARK: Delegate
    public func webRTCIsConnected() {
        guard !self.hasConnected else { return }
        self.hasConnected = true
        self.answerCallAction?.fulfill()
    }
    
    public func isRemoteVideoDidChange(isEnabled: Bool) {
        isRemoteVideoEnabled = isEnabled
    }
    
    public func didReceiveHangUpSignal() {
        self.hasEnded = true
        DispatchQueue.main.async {
            if let currentBanner = IncomingCallBanner.current { currentBanner.dismiss() }
            if let callVC = CurrentAppContext().frontmostViewController() as? CallVC { callVC.handleEndCallMessage() }
            if let miniCallView = MiniCallView.current { miniCallView.dismiss() }
            AppEnvironment.shared.callManager.reportCurrentCallEnded(reason: .remoteEnded)
        }
    }
    
    public func dataChannelDidOpen() {
        // Send initial video status
        if (isVideoEnabled) {
            webRTCSession.turnOnVideo()
        } else {
            webRTCSession.turnOffVideo()
        }
    }
}
