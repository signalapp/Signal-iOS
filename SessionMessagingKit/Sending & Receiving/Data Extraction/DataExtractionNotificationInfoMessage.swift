
@objc(SNDataExtractionNotificationInfoMessage)
final class DataExtractionNotificationInfoMessage : TSInfoMessage {
    private let kind: DataExtractionNotification.Kind
    
    init(kind: DataExtractionNotification.Kind, timestamp: UInt64, thread: TSThread) {
        self.kind = kind
        let infoMessageType: TSInfoMessageType
        switch kind {
        case .screenshot: infoMessageType = .screenshotNotification
        case .mediaSaved: infoMessageType = .mediaSavedNotification
        }
        super.init(timestamp: timestamp, in: thread, messageType: infoMessageType)
    }
    
    required init(coder: NSCoder) {
        preconditionFailure("Not implemented.")
    }
    
    required init(dictionary dictionaryValue: [String:Any]!) throws {
        preconditionFailure("Not implemented.")
    }
    
    override func previewText(with transaction: YapDatabaseReadTransaction) -> String {
        guard let thread = thread as? TSContactThread else { return "" } // Should never occur
        let sessionID = thread.contactIdentifier()
        let displayName = Storage.shared.getContact(with: sessionID)?.displayName(for: .regular) ?? sessionID
        switch kind {
        case .screenshot: return "\(displayName) took a screenshot."
        case .mediaSaved:
            // TODO: Use the timestamp and tell the user * which * media was saved
            return "Media saved by \(displayName)."
        }
    }
}
