
/// A message is invalidated when it needs to be re-rendered in the UI. Examples of when this happens include:
///
/// • When the sent or read status of a message is updated.
/// • When an attachment is uploaded or downloaded.
@objc public final class MessageInvalidator : NSObject {
    private static var invalidatedMessages: Set<String> = []
    
    @objc public static let shared = MessageInvalidator()
    
    private override init() { }
    
    @objc public static func invalidate(_ message: TSMessage, with transaction: YapDatabaseReadWriteTransaction) {
        guard let id = message.uniqueId else { return }
        invalidatedMessages.insert(id)
        message.touch(with: transaction)
    }
    
    @objc public static func isInvalidated(_ message: TSMessage) -> Bool {
        guard let id = message.uniqueId else { return false }
        return invalidatedMessages.contains(id)
    }
    
    @objc public static func markAsUpdated(_ id: String) {
        invalidatedMessages.remove(id)
    }
}
