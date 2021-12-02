
@objc public extension TSInfoMessage {
    @objc(fromCallOffer:associatedWith:)
    static func from(_ callMessage: CallMessage, associatedWith thread: TSThread) -> TSInfoMessage {
        return callInfoMessage(from: callMessage.sender!, timestamp: callMessage.sentTimestamp!, in: thread)
    }
    
    static func callInfoMessage(from caller: String, timestamp: UInt64, in thread: TSThread) -> TSInfoMessage {
        let callState: TSInfoMessageCallState
        if caller == getUserHexEncodedPublicKey() {
            callState = .outgoing
        } else {
            callState = .incoming
        }
        let infoMessage = TSInfoMessage(timestamp: timestamp, in: thread, messageType: .call)
        infoMessage.callState = callState
        return infoMessage
    }
    
    @objc(updateCallInfoMessageWithNewState:usingTransaction:)
    func updateCallInfoMessage(_ newCallState: TSInfoMessageCallState, using transaction: YapDatabaseReadWriteTransaction) {
        guard self.messageType == .call else { return }
        self.callState = newCallState
        self.save(with: transaction)
    }
}
