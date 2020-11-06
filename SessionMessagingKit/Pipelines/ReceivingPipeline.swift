import SessionUtilities

public enum ReceivingPipeline {

    public static func parse(_ data: Data) -> Message? {
        // TODO: Decrypt
        let proto: SNProtoContent
        do {
            proto = try SNProtoContent.parseData(data)
        } catch {
            SNLog("Couldn't parse proto due to error: \(error).")
            return nil
        }
        if let readReceipt = ReadReceipt.fromProto(proto) { return readReceipt }
        if let sessionRequest = SessionRequest.fromProto(proto) { return sessionRequest }
        if let typingIndicator = TypingIndicator.fromProto(proto) { return typingIndicator }
        if let closedGroupUpdate = ClosedGroupUpdate.fromProto(proto) { return closedGroupUpdate }
        if let expirationTimerUpdate = ExpirationTimerUpdate.fromProto(proto) { return expirationTimerUpdate }
        if let visibleMessage = VisibleMessage.fromProto(proto) { return visibleMessage }
        return nil
    }
}
