import Foundation

@objc(LKSessionCipher)
public final class LokiSessionCipher : SessionCipher {
    private let sessionResetImplementation: SessionRestorationProtocol?
    private let sessionStore: SessionStore
    private let preKeyStore: PreKeyStore
    private let recipientID: String
    private let deviceID: Int32
    
    @objc public static let newSessionAdoptedNotification = "LKNewSessionAdoptedNotification"
    @objc public static let contactKey = "LKContactKey"
    
    @objc public init(sessionResetImplementation: SessionRestorationProtocol, sessionStore: SessionStore, preKeyStore: PreKeyStore, signedPreKeyStore: SignedPreKeyStore, identityKeyStore: IdentityKeyStore, recipientID: String, deviceID: Int32) {
        self.sessionResetImplementation = sessionResetImplementation
        self.sessionStore = sessionStore
        self.preKeyStore = preKeyStore
        self.recipientID = recipientID
        self.deviceID = deviceID
        super.init(sessionStore: sessionStore, preKeyStore: preKeyStore, signedPreKeyStore: signedPreKeyStore, identityKeyStore: identityKeyStore, recipientId: recipientID, deviceId: deviceID)
    }
    
    @available(*, unavailable)
    override convenience private init(axolotlStore sessionStore: AxolotlStore, recipientId: String, deviceId: Int32) {
        self.init(sessionStore: sessionStore, preKeyStore: sessionStore, signedPreKeyStore: sessionStore, identityKeyStore: sessionStore, recipientId: recipientId, deviceId: deviceId)
    }
    
    override private init(sessionStore: SessionStore, preKeyStore: PreKeyStore, signedPreKeyStore: SignedPreKeyStore, identityKeyStore: IdentityKeyStore, recipientId: String, deviceId: Int32) {
        self.sessionResetImplementation = nil
        self.sessionStore = sessionStore
        self.preKeyStore = preKeyStore
        self.recipientID = recipientId
        self.deviceID = deviceId
        super.init(sessionStore: sessionStore, preKeyStore: preKeyStore, signedPreKeyStore: signedPreKeyStore, identityKeyStore: identityKeyStore, recipientId: recipientId, deviceId: deviceId)
    }
    
    override public func decrypt(_ whisperMessage: CipherMessage, protocolContext: Any?) throws -> Data {
        // Note that while decrypting our state may change internally
        let currentState = getCurrentState(protocolContext: protocolContext)
        if (currentState == nil && whisperMessage.cipherMessageType == .prekey) {
            try sessionResetImplementation?.validatePreKeyWhisperMessage(for: recipientID, whisperMessage: whisperMessage, using: protocolContext!)
        }
        let plainText = try super.decrypt(whisperMessage, protocolContext: protocolContext)
        handleSessionReset(for: whisperMessage, previousState: currentState, protocolContext: protocolContext!)
        return plainText
    }
    
    private func getCurrentState(protocolContext: Any?) -> SessionState? {
        let record = sessionStore.loadSession(recipientID, deviceId: deviceID, protocolContext: protocolContext)
        return record.isFresh() ? nil : record.sessionState()
    }
    
    private func handleSessionReset(for whisperMessage: CipherMessage, previousState: SessionState?, protocolContext: Any) {
        // Don't bother doing anything if we didn't have a session before
        guard let previousState = previousState else { return }
        let sessionResetStatus = sessionResetImplementation?.getSessionRestorationStatus(for: recipientID) ?? SessionRestorationStatus.none
        // Bail early if no session reset is in progress
        guard sessionResetStatus != .none else { return }
        let currentState = getCurrentState(protocolContext: protocolContext)
        // Check if our previous state and our current state differ
        if (currentState == nil || currentState!.aliceBaseKey != previousState.aliceBaseKey) {
            if sessionResetStatus == .requestReceived {
                // The other user used an old session to contact us. Wait for them to use a new one
                restoreSession(previousState, protocolContext: protocolContext)
            } else {
                // Our session reset went through successfully.
                // We initiated a session reset and got a different session back from the user.
                deleteAllSessions(except: currentState, protocolContext: protocolContext)
                notifySessionAdopted(protocolContext)
            }
        } else if sessionResetStatus == .requestReceived {
            // Our session reset went through successfully.
            // We got a message with the same session from the other user.
            deleteAllSessions(except: previousState, protocolContext: protocolContext)
            notifySessionAdopted(protocolContext)
        }
    }
    
    private func notifySessionAdopted(_ protocolContext: Any) {
        self.sessionResetImplementation?.handleNewSessionAdopted(for: recipientID, using: protocolContext)
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: LokiSessionCipher.newSessionAdoptedNotification), object: nil, userInfo: [ LokiSessionCipher.contactKey : recipientID ])
    }
    
    private func deleteAllSessions(except state: SessionState?, protocolContext: Any?) {
        let record = sessionStore.loadSession(recipientID, deviceId: deviceID, protocolContext: protocolContext)
        record.removePreviousSessionStates()
        let newState = state ?? SessionState()
        record.setState(newState)
        sessionStore.storeSession(recipientID, deviceId: deviceID, session: record, protocolContext: protocolContext)
    }
    
    private func restoreSession(_ state: SessionState, protocolContext: Any?) {
        let record = sessionStore.loadSession(recipientID, deviceId: deviceID, protocolContext: protocolContext)
        // Remove the state from previous session states
        record.previousSessionStates()?.enumerateObjects(options: .reverse) { obj, index, stop in
            guard let obj = obj as? SessionState, state.aliceBaseKey == obj.aliceBaseKey else { return }
            record.previousSessionStates()?.removeObject(at: index)
            stop.pointee = true
        }
        // Promote so the previous state gets archived
        record.promoteState(state)
        sessionStore.storeSession(recipientID, deviceId: deviceID, session: record, protocolContext: protocolContext)
    }
}
