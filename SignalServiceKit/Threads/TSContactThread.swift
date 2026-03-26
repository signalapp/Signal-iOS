//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB
import LibSignalClient

open class TSContactThread: TSThread {
    override public class var recordType: SDSRecordType { .contactThread }

    /// Represents the uppercase ServiceId string for this contact.
    /// - Note
    /// This property name includes `UUID` for compatibility with SDS (to match the
    /// SQLite column), but **may not contain a valid UUID string**.
    public internal(set) var contactUUID: String?
    public internal(set) var contactPhoneNumber: String?

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case contactPhoneNumber
        case contactUUID
        case hasDismissedOffers
    }

    public required init(inheritableDecoder decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contactUUID = try container.decodeIfPresent(String.self, forKey: .contactUUID)
        self.contactPhoneNumber = try container.decodeIfPresent(String.self, forKey: .contactPhoneNumber)
        try super.init(inheritableDecoder: decoder)
    }

    override public func encode(to encoder: any Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.contactUUID, forKey: .contactUUID)
        try container.encode(self.contactPhoneNumber, forKey: .contactPhoneNumber)
        try container.encode(false, forKey: .hasDismissedOffers)
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.contactPhoneNumber)
        hasher.combine(self.contactUUID)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.contactPhoneNumber == object.contactPhoneNumber else { return false }
        guard self.contactUUID == object.contactUUID else { return false }
        return true
    }

    init(
        id: Int64?,
        uniqueId: String,
        creationDate: Date?,
        editTargetTimestamp: UInt64?,
        isArchivedObsolete: Bool,
        isMarkedUnreadObsolete: Bool,
        lastDraftInteractionRowId: UInt64,
        lastDraftUpdateTimestamp: UInt64,
        lastInteractionRowId: UInt64,
        lastSentStoryTimestamp: UInt64?,
        mentionNotificationMode: TSThreadMentionNotificationMode,
        messageDraft: String?,
        messageDraftBodyRanges: MessageBodyRanges?,
        mutedUntilTimestampObsolete: UInt64,
        shouldThreadBeVisible: Bool,
        storyViewMode: TSThreadStoryViewMode,
        contactUUID: String?,
        contactPhoneNumber: String?,
    ) {
        self.contactUUID = contactUUID
        self.contactPhoneNumber = contactPhoneNumber
        super.init(
            id: id,
            uniqueId: uniqueId,
            creationDate: creationDate,
            editTargetTimestamp: editTargetTimestamp,
            isArchivedObsolete: isArchivedObsolete,
            isMarkedUnreadObsolete: isMarkedUnreadObsolete,
            lastDraftInteractionRowId: lastDraftInteractionRowId,
            lastDraftUpdateTimestamp: lastDraftUpdateTimestamp,
            lastInteractionRowId: lastInteractionRowId,
            lastSentStoryTimestamp: lastSentStoryTimestamp,
            mentionNotificationMode: mentionNotificationMode,
            messageDraft: messageDraft,
            messageDraftBodyRanges: messageDraftBodyRanges,
            mutedUntilTimestampObsolete: mutedUntilTimestampObsolete,
            shouldThreadBeVisible: shouldThreadBeVisible,
            storyViewMode: storyViewMode,
        )
    }

    public init(
        uniqueId: String = UUID().uuidString,
        contactUUID: String?,
        contactPhoneNumber: String?,
    ) {
        self.contactUUID = contactUUID
        self.contactPhoneNumber = contactPhoneNumber
        super.init(uniqueId: uniqueId)
    }

    override func deepCopy() -> TSThread {
        return TSContactThread(
            id: self.id,
            uniqueId: self.uniqueId,
            creationDate: self.creationDate,
            editTargetTimestamp: self.editTargetTimestamp,
            isArchivedObsolete: self.isArchivedObsolete,
            isMarkedUnreadObsolete: self.isMarkedUnreadObsolete,
            lastDraftInteractionRowId: self.lastDraftInteractionRowId,
            lastDraftUpdateTimestamp: self.lastDraftUpdateTimestamp,
            lastInteractionRowId: self.lastInteractionRowId,
            lastSentStoryTimestamp: self.lastSentStoryTimestamp,
            mentionNotificationMode: self.mentionNotificationMode,
            messageDraft: self.messageDraft,
            messageDraftBodyRanges: self.messageDraftBodyRanges,
            mutedUntilTimestampObsolete: self.mutedUntilTimestampObsolete,
            shouldThreadBeVisible: self.shouldThreadBeVisible,
            storyViewMode: self.storyViewMode,
            contactUUID: self.contactUUID,
            contactPhoneNumber: self.contactPhoneNumber,
        )
    }

    class func fetchContactThreadViaCache(uniqueId: String, transaction: DBReadTransaction) -> TSContactThread? {
        return fetchViaCache(uniqueId: uniqueId, transaction: transaction)
    }

    public var contactAddress: SignalServiceAddress {
        return SignalServiceAddress(serviceIdString: self.contactUUID, phoneNumber: self.contactPhoneNumber)
    }

    override public func recipientAddresses(with tx: DBReadTransaction) -> [SignalServiceAddress] {
        return [self.contactAddress]
    }

    override public var isNoteToSelf: Bool { self.contactAddress.isLocalAddress }

    override public func hasSafetyNumbers() -> Bool {
        return OWSIdentityManagerObjCBridge.identityKey(forAddress: self.contactAddress) != nil
    }

    static func contactAddress(fromThreadId threadUniqueId: String, transaction tx: DBReadTransaction) -> SignalServiceAddress? {
        return (TSThread.fetchViaCache(uniqueId: threadUniqueId, transaction: tx) as? TSContactThread)?.contactAddress
    }

    override public func anyDidInsert(transaction: DBWriteTransaction) {
        super.anyDidInsert(transaction: transaction)
        Logger.info("Inserted contact thread: \(self.contactAddress)")
    }

    @objc
    public convenience init(contactAddress: SignalServiceAddress) {
        let normalizedAddress = NormalizedDatabaseRecordAddress(address: contactAddress)
        owsAssertDebug(normalizedAddress != nil)
        self.init(
            contactUUID: normalizedAddress?.serviceId?.serviceIdUppercaseString,
            contactPhoneNumber: normalizedAddress?.phoneNumber,
        )
    }

    @objc
    public static func getOrCreateLocalThread(transaction: DBWriteTransaction) -> TSContactThread? {
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aciAddress else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
    }

    @objc
    public static func getOrCreateLocalThreadWithSneakyTransaction() -> TSContactThread? {
        assert(!Thread.isMainThread)

        let thread: TSContactThread? = SSKEnvironment.shared.databaseStorageRef.read { tx in
            guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
                owsFailDebug("Missing localAddress.")
                return nil
            }
            return TSContactThread.getWithContactAddress(localAddress, transaction: tx)
        }
        if let thread {
            return thread
        }

        return SSKEnvironment.shared.databaseStorageRef.write { transaction in
            return getOrCreateLocalThread(transaction: transaction)
        }
    }

    @objc
    public static func getOrCreateThread(
        withContactAddress contactAddress: SignalServiceAddress,
        transaction: DBWriteTransaction,
    ) -> TSContactThread {
        owsAssertDebug(contactAddress.isValid)

        let existingThread = ContactThreadFinder().contactThread(for: contactAddress, tx: transaction)
        if let existingThread {
            return existingThread
        }

        let insertedThread = TSContactThread(contactAddress: contactAddress)
        insertedThread.anyInsert(transaction: transaction)
        return insertedThread
    }

    public static func getOrCreateThread(contactAddress: SignalServiceAddress) -> TSContactThread {
        owsAssertDebug(contactAddress.isValid)
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        let existingThread = databaseStorage.read { tx in
            return ContactThreadFinder().contactThread(for: contactAddress, tx: tx)
        }
        if let existingThread {
            return existingThread
        }

        return databaseStorage.write { tx in
            return self.getOrCreateThread(withContactAddress: contactAddress, transaction: tx)
        }
    }

    // Unlike getOrCreateThreadWithContactAddress, this will _NOT_ create a thread if one does not already exist.
    @objc
    public static func getWithContactAddress(
        _ contactAddress: SignalServiceAddress,
        transaction: DBReadTransaction,
    ) -> TSContactThread? {
        return ContactThreadFinder().contactThread(for: contactAddress, tx: transaction)
    }
}

// MARK: - StringInterpolation

public extension String.StringInterpolation {
    mutating func appendInterpolation(contactThreadColumn column: TSContactThread.CodingKeys) {
        appendLiteral(column.rawValue)
    }

    mutating func appendInterpolation(contactThreadColumnFullyQualified column: TSContactThread.CodingKeys) {
        appendLiteral("\(TSThread.databaseTableName).\(column.rawValue)")
    }
}
