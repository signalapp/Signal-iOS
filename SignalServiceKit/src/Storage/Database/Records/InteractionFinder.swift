//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

protocol InteractionFinderAdapter {
    associatedtype ReadTransaction

    static func fetch(uniqueId: String, transaction: ReadTransaction) throws -> TSInteraction?

    static func mostRecentSortId(transaction: ReadTransaction) -> UInt64

    static func existsIncomingMessage(timestamp: UInt64, address: SignalServiceAddress, sourceDeviceId: UInt32, transaction: ReadTransaction) -> Bool

    func mostRecentInteraction(transaction: ReadTransaction) -> TSInteraction?
    func mostRecentInteractionForInbox(transaction: ReadTransaction) -> TSInteraction?

    func sortIndex(interactionUniqueId: String, transaction: ReadTransaction) throws -> UInt?
    func count(transaction: ReadTransaction) -> UInt
    func unreadCount(transaction: ReadTransaction) throws -> UInt
    func enumerateInteractionIds(transaction: ReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws
    func enumerateInteractions(transaction: ReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws
    func enumerateUnseenInteractions(transaction: ReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws

    func interaction(at index: UInt, transaction: ReadTransaction) throws -> TSInteraction?

    static func interactions(withTimestamp timestamp: UInt64, filter: @escaping (TSInteraction) -> Bool, transaction: ReadTransaction) throws -> [TSInteraction]

    static func incompleteCallIds(transaction: ReadTransaction) -> [String]
}

// MARK: -

@objc
public class InteractionFinder: NSObject, InteractionFinderAdapter {

    let yapAdapter: YAPDBInteractionFinderAdapter
    let grdbAdapter: GRDBInteractionFinderAdapter

    @objc
    public init(threadUniqueId: String) {
        self.yapAdapter = YAPDBInteractionFinderAdapter(threadUniqueId: threadUniqueId)
        self.grdbAdapter = GRDBInteractionFinderAdapter(threadUniqueId: threadUniqueId)
    }

    // MARK: - static methods

    @objc
    public class func fetchSwallowingErrors(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSInteraction? {
        do {
            return try fetch(uniqueId: uniqueId, transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    public class func fetch(uniqueId: String, transaction: SDSAnyReadTransaction) throws -> TSInteraction? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.fetch(uniqueId: uniqueId, transaction: yapRead)
        case .grdbRead(let grdbRead):
            return try GRDBInteractionFinderAdapter.fetch(uniqueId: uniqueId, transaction: grdbRead)
        }
    }

    @objc
    public class func mostRecentSortId(transaction: SDSAnyReadTransaction) -> UInt64 {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.mostRecentSortId(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinderAdapter.mostRecentSortId(transaction: grdbRead)
        }
    }

    @objc
    public class func existsIncomingMessage(timestamp: UInt64, address: SignalServiceAddress, sourceDeviceId: UInt32, transaction: SDSAnyReadTransaction) -> Bool {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.existsIncomingMessage(timestamp: timestamp, address: address, sourceDeviceId: sourceDeviceId, transaction: yapRead)
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinderAdapter.existsIncomingMessage(timestamp: timestamp, address: address, sourceDeviceId: sourceDeviceId, transaction: grdbRead)
        }
    }

    // MARK: - instance methods

    @objc
    public func mostRecentInteraction(transaction: SDSAnyReadTransaction) -> TSInteraction? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.mostRecentInteraction(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.mostRecentInteraction(transaction: grdbRead)
        }
    }

    @objc
    func mostRecentInteractionForInbox(transaction: SDSAnyReadTransaction) -> TSInteraction? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.mostRecentInteractionForInbox(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.mostRecentInteractionForInbox(transaction: grdbRead)
        }
    }

    public func sortIndex(interactionUniqueId: String, transaction: SDSAnyReadTransaction) throws -> UInt? {
        return try Bench(title: "sortIndex") {
            switch transaction.readTransaction {
            case .yapRead(let yapRead):
                return yapAdapter.sortIndex(interactionUniqueId: interactionUniqueId, transaction: yapRead)
            case .grdbRead(let grdbRead):
                return try grdbAdapter.sortIndex(interactionUniqueId: interactionUniqueId, transaction: grdbRead)
            }
        }
    }

    @objc
    public func count(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.count(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.count(transaction: grdbRead)
        }
    }

    public func unreadCount(transaction: SDSAnyReadTransaction) throws -> UInt {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.unreadCount(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.unreadCount(transaction: grdbRead)
        }
    }

    public func enumerateInteractionIds(transaction: SDSAnyReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try yapAdapter.enumerateInteractionIds(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateInteractionIds(transaction: grdbRead, block: block)
        }
    }

    @objc
    public func enumerateInteractionIdsObjc(transaction: SDSAnyReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try yapAdapter.enumerateInteractionIds(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateInteractionIds(transaction: grdbRead, block: block)
        }
    }

    @objc
    public func enumerateInteractions(transaction: SDSAnyReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try yapAdapter.enumerateInteractions(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateInteractions(transaction: grdbRead, block: block)
        }
    }

    @objc
    public func enumerateUnseenInteractions(transaction: SDSAnyReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try yapAdapter.enumerateUnseenInteractions(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateUnseenInteractions(transaction: grdbRead, block: block)
        }
    }

    public func interaction(at index: UInt, transaction: SDSAnyReadTransaction) throws -> TSInteraction? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.interaction(at: index, transaction: yapRead)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.interaction(at: index, transaction: grdbRead)
        }
    }

    @objc
    public class func interactions(withTimestamp timestamp: UInt64, filter: @escaping (TSInteraction) -> Bool, transaction: SDSAnyReadTransaction) throws -> [TSInteraction] {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try YAPDBInteractionFinderAdapter.interactions(withTimestamp: timestamp,
                                                                  filter: filter,
                                                                  transaction: yapRead)
        case .grdbRead(let grdbRead):
            return try GRDBInteractionFinderAdapter.interactions(withTimestamp: timestamp,
                                                                 filter: filter,
                                                                 transaction: grdbRead)
        }
    }

    @objc
    public class func incompleteCallIds(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.incompleteCallIds(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinderAdapter.incompleteCallIds(transaction: grdbRead)
        }
    }
}

// MARK: -

struct YAPDBInteractionFinderAdapter: InteractionFinderAdapter {

    private let threadUniqueId: String

    init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    static func fetch(uniqueId: String, transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        return transaction.object(forKey: uniqueId, inCollection: TSInteraction.collection()) as? TSInteraction
    }

    static func mostRecentSortId(transaction: YapDatabaseReadTransaction) -> UInt64 {
        return SSKIncrementingIdFinder.previousId(key: TSInteraction.collection(), transaction: transaction)
    }

    static func existsIncomingMessage(timestamp: UInt64, address: SignalServiceAddress, sourceDeviceId: UInt32, transaction: YapDatabaseReadTransaction) -> Bool {
        return OWSIncomingMessageFinder().existsMessage(withTimestamp: timestamp, address: address, sourceDeviceId: sourceDeviceId, transaction: transaction)
    }

    // MARK: - instance methods

    func mostRecentInteraction(transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        guard let view = interactionExt(transaction) else {
            return nil
        }
        return view.lastObject(inGroup: threadUniqueId) as? TSInteraction
    }

    func mostRecentInteractionForInbox(transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        var last: TSInteraction?
        var missedCount: UInt = 0
        guard let view = interactionExt(transaction) else {
            return nil
        }
        view.safe_enumerateKeysAndObjects(inGroup: threadUniqueId,
                                          extensionName: TSMessageDatabaseViewExtensionName,
                                          with: NSEnumerationOptions.reverse) { (_, _, object, _, stopPtr) in
            guard let interaction = object as? TSInteraction else {
                owsFailDebug("unexpected interaction: \(type(of: object))")
                return
            }
            if TSThread.shouldInteractionAppear(inInbox: interaction) {
                last = interaction
                stopPtr.pointee = true
            }

            missedCount += 1
            // For long ignored threads, with lots of SN changes this can get really slow.
            // I see this in development because I have a lot of long forgotten threads with
            // members who's test devices are constantly reinstalled. We could add a
            // purpose-built DB view, but I think in the real world this is rare to be a
            // hotspot.
            if (missedCount > 50) {
                Logger.warn("found last interaction for inbox after skipping \(missedCount) items")
            }
        }
        return last
    }

    func count(transaction: YapDatabaseReadTransaction) -> UInt {
        guard let view = interactionExt(transaction) else {
            return 0
        }
        return view.numberOfItems(inGroup: threadUniqueId)
    }

    func unreadCount(transaction: YapDatabaseReadTransaction) -> UInt {
        guard let view = unreadExt(transaction) else {
            return 0
        }
        return view.numberOfItems(inGroup: threadUniqueId)
    }

    func sortIndex(interactionUniqueId: String, transaction: YapDatabaseReadTransaction) -> UInt? {
        var index: UInt = 0
        guard let view = interactionExt(transaction) else {
            return nil
        }
        let wasFound = view.getGroup(nil, index: &index, forKey: interactionUniqueId, inCollection: collection)

        guard wasFound else {
            return nil
        }

        return index
    }

    func enumerateInteractionIds(transaction: YapDatabaseReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {
        var errorToRaise: Error?
        guard let view = interactionExt(transaction) else {
            return
        }
        view.enumerateKeys(inGroup: threadUniqueId, with: NSEnumerationOptions.reverse) { (_, key, _, stopPtr) in
            do {
                try block(key, stopPtr)
            } catch {
                // the block parameter is a `throws` block because the GRDB implementation can throw
                // we don't expect this with YapDB, though we still try to handle it.
                owsFailDebug("unexpected error: \(error)")
                stopPtr.pointee = true
                errorToRaise = error
            }
        }
        if let errorToRaise = errorToRaise {
            throw errorToRaise
        }
    }

    func enumerateInteractions(transaction: YapDatabaseReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        guard let view = interactionExt(transaction) else {
            return
        }
        view.safe_enumerateKeysAndObjects(inGroup: threadUniqueId,
                                          extensionName: TSMessageDatabaseViewExtensionName,
                                          with: NSEnumerationOptions.reverse) { (_, _, object, _, stopPtr) in
                                            guard let interaction = object as? TSInteraction else {
                                                owsFailDebug("unexpected interaction: \(type(of: object))")
                                                return
                                            }
                                            block(interaction, stopPtr)
        }
    }

    func enumerateUnseenInteractions(transaction: YapDatabaseReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        guard let view = unseenExt(transaction) else {
            return
        }
        view.safe_enumerateKeysAndObjects(inGroup: threadUniqueId,
                                          extensionName: TSUnseenDatabaseViewExtensionName,
                                          with: []) { (_, _, object, _, stopPtr) in
                                            guard let interaction = object as? TSInteraction else {
                                                owsFailDebug("unexpected interaction: \(type(of: object))")
                                                return
                                            }
            block(interaction, stopPtr)
        }
    }

    func interaction(at index: UInt, transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        guard let view = interactionExt(transaction) else {
            return nil
        }
        guard let obj = view.object(at: index, inGroup: threadUniqueId) else {
            return nil
        }

        guard let interaction = obj as? TSInteraction else {
            owsFailDebug("unexpected interaction: \(type(of: obj))")
            return nil
        }

        return interaction
    }

    static func incompleteCallIds(transaction: YapDatabaseReadTransaction) -> [String] {
        return OWSIncompleteCallsJob.ydb_incompleteCallIds(with: transaction)
    }

    static func interactions(withTimestamp timestamp: UInt64, filter: @escaping (TSInteraction) -> Bool, transaction: YapDatabaseReadTransaction) throws -> [TSInteraction] {
        return TSInteraction.ydb_interactions(withTimestamp: timestamp,
                                              filter: filter,
                                              with: transaction)
    }

    // MARK: - private

    private var collection: String {
        return TSInteraction.collection()
    }

    private func unreadExt(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction? {
        return transaction.safeViewTransaction(TSUnreadDatabaseViewExtensionName)
    }

    private func interactionExt(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction? {
        return transaction.safeViewTransaction(TSMessageDatabaseViewExtensionName)
    }

    private func unseenExt(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction? {
        return transaction.safeViewTransaction(TSUnseenDatabaseViewExtensionName)
    }
}

// MARK: -

struct GRDBInteractionFinderAdapter: InteractionFinderAdapter {

    typealias ReadTransaction = GRDBReadTransaction

    let threadUniqueId: String

    init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    static func fetch(uniqueId: String, transaction: GRDBReadTransaction) throws -> TSInteraction? {
        return TSInteraction.anyFetch(uniqueId: uniqueId, transaction: transaction.asAnyRead)
    }

    static func mostRecentSortId(transaction: GRDBReadTransaction) -> UInt64 {
        do {
            let sql = """
                SELECT seq
                FROM sqlite_sequence
                WHERE name = ?
            """
            guard let value = try UInt64.fetchOne(transaction.database, sql: sql, arguments: [InteractionRecord.databaseTableName]) else {
                return 0
            }
            return value
        } catch {
            owsFailDebug("Read failed: \(error).")
            return 0
        }
    }

    static func existsIncomingMessage(timestamp: UInt64, address: SignalServiceAddress, sourceDeviceId: UInt32, transaction: GRDBReadTransaction) -> Bool {
        var exists = false
        if let uuidString = address.uuidString {
            let sql = """
                SELECT EXISTS(
                    SELECT 1
                    FROM \(InteractionRecord.databaseTableName)
                    WHERE \(interactionColumn: .timestamp) = ?
                    AND \(interactionColumn: .authorUUID) = ?
                    AND \(interactionColumn: .sourceDeviceId) = ?
                )
            """
            let arguments: StatementArguments = [timestamp, uuidString, sourceDeviceId]
            exists = try! Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
        }

        if !exists, let phoneNumber = address.phoneNumber {
            let sql = """
                SELECT EXISTS(
                    SELECT 1
                    FROM \(InteractionRecord.databaseTableName)
                    WHERE \(interactionColumn: .timestamp) = ?
                    AND \(interactionColumn: .authorPhoneNumber) = ?
                    AND \(interactionColumn: .sourceDeviceId) = ?
                )
            """
            let arguments: StatementArguments = [timestamp, phoneNumber, sourceDeviceId]
            exists = try! Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
        }

        return exists
    }

    // MARK: - instance methods

    func mostRecentInteraction(transaction: GRDBReadTransaction) -> TSInteraction? {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        ORDER BY \(interactionColumn: .id) DESC
        """
        let arguments: StatementArguments = [threadUniqueId]
        return TSInteraction.grdbFetchOne(sql: sql, arguments: arguments, transaction: transaction)
    }

    func mostRecentInteractionForInbox(transaction: GRDBReadTransaction) -> TSInteraction? {
        let sql = """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .errorType) IS NOT ?
                AND \(interactionColumn: .messageType) IS NOT ?
                ORDER BY \(interactionColumn: .id) DESC
                """
        let arguments: StatementArguments = [threadUniqueId, TSErrorMessageType.nonBlockingIdentityChange.rawValue, TSInfoMessageType.verificationStateChange.rawValue]
        return TSInteraction.grdbFetchOne(sql: sql, arguments: arguments, transaction: transaction)
    }

    func sortIndex(interactionUniqueId: String, transaction: GRDBReadTransaction) throws -> UInt? {
        return try UInt.fetchOne(transaction.database,
                                 sql: """
            SELECT rowNumber
            FROM (
                SELECT
                    ROW_NUMBER() OVER (ORDER BY \(interactionColumn: .id)) as rowNumber,
                    \(interactionColumn: .id),
                    \(interactionColumn: .uniqueId)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
            )
            WHERE \(interactionColumn: .uniqueId) = ?
            """,
            arguments: [threadUniqueId, interactionUniqueId])
    }

    func count(transaction: GRDBReadTransaction) -> UInt {
        do {
            guard let count = try UInt.fetchOne(transaction.database,
                                                sql: """
                SELECT COUNT(*)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                """,
                arguments: [threadUniqueId]) else {
                    throw assertionError("count was unexpectedly nil")
            }
            return count
        } catch {
            owsFail("error: \(error)")
        }
    }

    func unreadCount(transaction: GRDBReadTransaction) throws -> UInt {
        guard let count = try UInt.fetchOne(transaction.database,
                                            sql: """
            SELECT COUNT(*)
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .read) is 0
            """,
            arguments: [threadUniqueId]) else {
                throw assertionError("count was unexpectedly nil")
        }
        return count
    }

    func enumerateInteractionIds(transaction: GRDBReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {

        let cursor = try String.fetchCursor(transaction.database,
                                            sql: """
            SELECT \(interactionColumn: .uniqueId)
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            ORDER BY \(interactionColumn: .id) DESC
            """,
            arguments: [threadUniqueId])
        while let uniqueId = try cursor.next() {
            var stop: ObjCBool = false
            try block(uniqueId, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    func enumerateUnseenInteractions(transaction: GRDBReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {

        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        AND \(interactionColumn: .read) is 0
        """
        let arguments: [DatabaseValueConvertible] = [threadUniqueId]
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction)
        while let interaction = try cursor.next() {
            var stop: ObjCBool = false
            if interaction as? OWSReadTracking == nil {
                owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
            }
            block(interaction, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    func enumerateInteractions(transaction: GRDBReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        try enumerateInteractionIds(transaction: transaction) { (uniqueId, stop) in
            guard let interaction = TSInteraction.anyFetch(uniqueId: uniqueId, transaction: transaction.asAnyRead) else {
                owsFailDebug("Couldn't load interaction.")
                return
            }
            block(interaction, stop)
        }
    }

    func interaction(at index: UInt, transaction: GRDBReadTransaction) throws -> TSInteraction? {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        ORDER BY \(interactionColumn: .id) DESC
        LIMIT 1
        OFFSET ?
        """
        let arguments: StatementArguments = [threadUniqueId, index]
        return TSInteraction.grdbFetchOne(sql: sql, arguments: arguments, transaction: transaction)
    }

    static func interactions(withTimestamp timestamp: UInt64, filter: @escaping (TSInteraction) -> Bool, transaction: ReadTransaction) throws -> [TSInteraction] {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .timestamp) = ?
        """
        let arguments: [DatabaseValueConvertible] = [timestamp]

        let unfiltered = try TSInteraction.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction).all()
        return unfiltered.filter(filter)
    }

    static func incompleteCallIds(transaction: ReadTransaction) -> [String] {
        let sql: String = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .recordType) = ?
        AND ( \(interactionColumn: .callType) = ?
        OR \(interactionColumn: .callType) = ? )
        """
        let statementArguments: StatementArguments = [
            SDSRecordType.call.rawValue,
            RPRecentCallType.outgoingIncomplete.rawValue,
            RPRecentCallType.incomingIncomplete.rawValue
        ]
        var result = [String]()
        do {
            let cursor = try String.fetchCursor(transaction.database,
                                                sql: sql,
                                                arguments: statementArguments)
            while let uniqueId = try cursor.next() {
                result.append(uniqueId)
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }
}

private func assertionError(_ description: String) -> Error {
    return OWSErrorMakeAssertionError(description)
}
