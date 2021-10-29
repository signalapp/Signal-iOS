import Foundation
import WebRTC
import SessionMessagingKit

public final class SessionCall: NSObject {
    // MARK: Metadata Properties
    let uuid: UUID
    let sessionID: String
    let mode: Mode
    let webRTCSession: WebRTCSession
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
    
    // MARK: Mode
    enum Mode {
        case offer
        case answer(sdp: RTCSessionDescription)
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

    var duration: TimeInterval {
        guard let connectedDate = connectedDate else {
            return 0
        }

        return Date().timeIntervalSince(connectedDate)
    }
    
    // MARK: Initialization
    init(for sessionID: String, uuid: String, mode: Mode) {
        self.sessionID = sessionID
        self.uuid = UUID(uuidString: uuid)!
        self.mode = mode
        self.webRTCSession = WebRTCSession.current ?? WebRTCSession(for: sessionID, with: uuid)
        super.init()
        reportIncomingCallIfNeeded()
    }
    
    func reportIncomingCallIfNeeded() {
        guard case .answer(_) = mode else { return }
        AppEnvironment.shared.callManager.reportIncomingCall(self, callerName: contactName) { error in
            if let error = error {
                SNLog("[Calls] Failed to report incoming call to CallKit due to error: \(error)")
            }
        }
    }
    
    // MARK: Actions
    func startSessionCall(completion: (() -> Void)?) {
        guard case .offer = mode else { return }
        AppEnvironment.shared.callManager.reportOutgoingCall(self)
        Storage.write { transaction in
            self.webRTCSession.sendPreOffer(to: self.sessionID, using: transaction).done {
                self.webRTCSession.sendOffer(to: self.sessionID, using: transaction).done {
                    self.hasStartedConnecting = true
                }.retainUntilComplete()
            }.retainUntilComplete()
        }
        completion?()
    }
    
    func answerSessionCall(completion: (() -> Void)?) {
        guard case let .answer(sdp) = mode else { return }
        hasStartedConnecting = true
        webRTCSession.handleRemoteSDP(sdp, from: sessionID) // This sends an answer message internally
        completion?()
    }
    
    func endSessionCall() {
        guard !hasEnded else { return }
        Storage.write { transaction in
            self.webRTCSession.endCall(with: self.sessionID, using: transaction)
        }
        hasEnded = true
        AppEnvironment.shared.callManager.reportCurrentCallEnded()
    }
}
