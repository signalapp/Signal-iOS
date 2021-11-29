
@objc public extension TSInfoMessage {
    @objc(fromCallOffer:associatedWith:)
    static func from(_ callMessage: CallMessage, associatedWith thread: TSThread) -> TSInfoMessage {
        return callInfoMessage(from: callMessage.sender!, timestamp: callMessage.sentTimestamp!, in: thread)
    }
    
    static func callInfoMessage(from caller: String, timestamp: UInt64, in thread: TSThread) -> TSInfoMessage {
        let callState: TSInfoMessageCallState
        let messageBody: String
        var contactName: String = ""
        if let contactThread = thread as? TSContactThread {
            let sessionID =  contactThread.contactSessionID()
            contactName = Storage.shared.getContact(with: sessionID)?.displayName(for: Contact.Context.regular) ?? sessionID
        }
        if caller == getUserHexEncodedPublicKey() {
            callState = .outgoing
            messageBody = String(format: NSLocalizedString("call_outgoing", comment: ""), contactName)
        } else {
            callState = .incoming
            messageBody = String(format: NSLocalizedString("call_incoming", comment: ""), contactName)
        }
        let infoMessage = TSInfoMessage.init(timestamp: timestamp, in: thread, messageType: .call, customMessage: messageBody)
        infoMessage.callState = callState
        return infoMessage
    }
    
    @objc(updateCallInfoMessageWithNewState:usingTransaction:)
    func updateCallInfoMessage(_ newCallState: TSInfoMessageCallState, using transaction: YapDatabaseReadWriteTransaction) {
        guard self.messageType == .call else { return }
        self.callState = newCallState
        var contactName: String = ""
        if let contactThread = self.thread as? TSContactThread {
            let sessionID =  contactThread.contactSessionID()
            contactName = Storage.shared.getContact(with: sessionID)?.displayName(for: Contact.Context.regular) ?? sessionID
        }
        self.customMessage = String(format: NSLocalizedString("call_missed", comment: ""), contactName)
        self.save(with: transaction)
    }
}
