
@objc(SNDataExtractionNotificationInfoMessage)
final class DataExtractionNotificationInfoMessage : TSInfoMessage {
    
    init(type: TSInfoMessageType, sentTimestamp: UInt64, thread: TSThread, referencedAttachmentTimestamp: UInt64?) {
        super.init(timestamp: sentTimestamp, in: thread, messageType: type)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    required init(dictionary dictionaryValue: [String:Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }
    
    override func previewText(with transaction: YapDatabaseReadTransaction) -> String {
        guard let thread = thread as? TSContactThread else { return "" } // Should never occur
        let sessionID = thread.contactSessionID()
        let displayName = Storage.shared.getContact(with: sessionID)?.displayName(for: .regular) ?? sessionID
        switch messageType {
        case .screenshotNotification: return String(format: NSLocalizedString("screenshot_taken", comment: ""), displayName)
        case .mediaSavedNotification:
            // TODO: Use referencedAttachmentTimestamp to tell the user * which * media was saved
            return String(format: NSLocalizedString("meida_saved", comment: ""), displayName)
        default: preconditionFailure()
        }
    }
}
