//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

protocol InteractionFinderAdapter {
    associatedtype ReadTransaction

    static func fetch(uniqueId: String, transaction: ReadTransaction) throws -> TSInteraction?

    func mostRecentInteraction(transaction: ReadTransaction) -> TSInteraction?
    func mostRecentInteractionForInbox(transaction: ReadTransaction) -> TSInteraction?

    func sortIndex(interactionUniqueId: String, transaction: ReadTransaction) throws -> UInt?
    func count(transaction: ReadTransaction) throws -> UInt
    func enumerateInteractionIds(transaction: ReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws
}

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

    public func count(transaction: SDSAnyReadTransaction) throws -> UInt {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.count(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.count(transaction: grdbRead)
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
}

struct YAPDBInteractionFinderAdapter: InteractionFinderAdapter {

    static let extensionName: String = TSMessageDatabaseViewExtensionName

    private let threadUniqueId: String

    init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    static func fetch(uniqueId: String, transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        return transaction.object(forKey: uniqueId, inCollection: TSInteraction.collection()) as? TSInteraction
    }

    // MARK: - instance methods

    func mostRecentInteraction(transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        return ext(transaction).lastObject(inGroup: threadUniqueId) as? TSInteraction
    }

    func mostRecentInteractionForInbox(transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        var last: TSInteraction?
        var missedCount: UInt = 0
        ext(transaction).enumerateKeysAndObjects(inGroup: threadUniqueId, with: NSEnumerationOptions.reverse) { (_, _, object, _, stopPtr) in
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
        return ext(transaction).numberOfItems(inGroup: threadUniqueId)
    }

    func sortIndex(interactionUniqueId: String, transaction: YapDatabaseReadTransaction) -> UInt? {
        var index: UInt = 0
        let wasFound = ext(transaction).getGroup(nil, index: &index, forKey: interactionUniqueId, inCollection: collection)

        guard wasFound else {
            return nil
        }

        return index
    }

    func enumerateInteractionIds(transaction: YapDatabaseReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {
        var errorToRaise: Error?
        ext(transaction).enumerateKeys(inGroup: threadUniqueId, with: NSEnumerationOptions.reverse) { (_, key, _, stopPtr) in
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

    // MARK: - private

    private var collection: String {
        return TSInteraction.collection()
    }

    private func ext(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction {
        return transaction.ext(type(of: self).extensionName) as! YapDatabaseViewTransaction
    }
}

struct GRDBInteractionFinderAdapter: InteractionFinderAdapter {

    typealias ReadTransaction = GRDBReadTransaction

    let threadUniqueId: String

    init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    static func fetch(uniqueId: String, transaction: GRDBReadTransaction) throws -> TSInteraction? {
        guard let interactionRecord = try InteractionRecord.fetchOne(transaction.database,
                                                                     sql: "SELECT * FROM \(InteractionRecord.databaseTableName) WHERE \(interactionColumn: .uniqueId) = ?",
            arguments: [uniqueId]) else {
                return nil
        }

        return TSInteraction.fromRecord(interactionRecord)
    }

    // MARK: - instance methods

    func mostRecentInteraction(transaction: GRDBReadTransaction) -> TSInteraction? {
        guard let interactionRecord = try! InteractionRecord.fetchOne(transaction.database,
                                                                     sql: """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            ORDER BY \(interactionColumn: .id) DESC
            """,
            arguments: [threadUniqueId]) else {
                return nil
        }

        return TSInteraction.fromRecord(interactionRecord)
    }

    func mostRecentInteractionForInbox(transaction: GRDBReadTransaction) -> TSInteraction? {
        guard let interactionRecord = try! InteractionRecord.fetchOne(transaction.database,
                                                                     sql: """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .errorType) IS NOT ?
            AND \(interactionColumn: .messageType) IS NOT ?
            ORDER BY \(interactionColumn: .id) DESC
            """,
            arguments: [threadUniqueId, TSErrorMessageType.nonBlockingIdentityChange, TSInfoMessageType.verificationStateChange]) else {
                return nil
        }

        return TSInteraction.fromRecord(interactionRecord)
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

    func count(transaction: GRDBReadTransaction) throws -> UInt {
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
    }

    func enumerateInteractionIds(transaction: GRDBReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {
        var stop: ObjCBool = false

        try String.fetchCursor(transaction.database,
                           sql: """
            SELECT \(interactionColumn: .uniqueId)
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            ORDER BY \(interactionColumn: .id) DESC
""",
            arguments: [threadUniqueId]).forEach { (uniqueId: String) -> Void in

            if stop.boolValue {
                return
            }

            try block(uniqueId, &stop)
        }
    }
}

private func assertionError(_ description: String) -> Error {
    return OWSErrorMakeAssertionError(description)
}
