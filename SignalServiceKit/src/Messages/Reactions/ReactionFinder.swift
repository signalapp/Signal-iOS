//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

protocol ReactionFinderAdapter {
    associatedtype ReadTransaction
    associatedtype WriteTransaction

    func reaction(for reactor: SignalServiceAddress, transaction: ReadTransaction) -> OWSReaction?
    func reactors(for emoji: String, transaction: ReadTransaction) -> [SignalServiceAddress]?
    func emojiCounts(transaction: ReadTransaction) -> [(emoji: String, count: Int)]?
    func existsReaction(transaction: ReadTransaction) -> Bool
    func enumerateReactions(
        transaction: ReadTransaction,
        block: @escaping (OWSReaction, UnsafeMutablePointer<ObjCBool>) -> Void
    )
    func allUniqueIds(transaction: ReadTransaction) -> [String]?

    func deleteAllReactions(transaction: WriteTransaction) throws
    static func deleteReactions(with uniqueIds: [String], transaction: WriteTransaction) throws
}

// MARK: -

@objc
public class ReactionFinder: NSObject, ReactionFinderAdapter {

    let yapAdapter: YAPDBReactionFinderAdapter
    let grdbAdapter: GRDBReactionFinderAdapter

    @objc
    public init(uniqueMessageId: String) {
        self.yapAdapter = YAPDBReactionFinderAdapter(uniqueMessageId: uniqueMessageId)
        self.grdbAdapter = GRDBReactionFinderAdapter(uniqueMessageId: uniqueMessageId)
    }

    @objc
    func reaction(for reactor: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSReaction? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.reaction(for: reactor, transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.reaction(for: reactor, transaction: grdbRead)
        }
    }

    @objc
    func reactors(for emoji: String, transaction: SDSAnyReadTransaction) -> [SignalServiceAddress]? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.reactors(for: emoji, transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.reactors(for: emoji, transaction: grdbRead)
        }
    }

    func emojiCounts(transaction: SDSAnyReadTransaction) -> [(emoji: String, count: Int)]? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.emojiCounts(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.emojiCounts(transaction: grdbRead)
        }
    }

    @objc
    func existsReaction(transaction: SDSAnyReadTransaction) -> Bool {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.existsReaction(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.existsReaction(transaction: grdbRead)
        }
    }

    @objc
    func enumerateReactions(
        transaction: SDSAnyReadTransaction,
        block: @escaping (OWSReaction, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.enumerateReactions(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return grdbAdapter.enumerateReactions(transaction: grdbRead, block: block)
        }
    }

    @objc
    func allUniqueIds(transaction: SDSAnyReadTransaction) -> [String]? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.allUniqueIds(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.allUniqueIds(transaction: grdbRead)
        }
    }

    @objc
    func deleteAllReactions(transaction: SDSAnyWriteTransaction) throws {
        switch transaction.writeTransaction {
        case .yapWrite(let yapWrite):
            return try yapAdapter.deleteAllReactions(transaction: yapWrite)
        case .grdbWrite(let grdbWrite):
            return try grdbAdapter.deleteAllReactions(transaction: grdbWrite)
        }
    }

    @objc
    static func deleteReactions(with uniqueIds: [String], transaction: SDSAnyWriteTransaction) throws {
        switch transaction.writeTransaction {
        case .yapWrite(let yapWrite):
            return try YAPDBReactionFinderAdapter.deleteReactions(with: uniqueIds, transaction: yapWrite)
        case .grdbWrite(let grdbWrite):
            return try GRDBReactionFinderAdapter.deleteReactions(with: uniqueIds, transaction: grdbWrite)
        }
    }
}

// MARK: -

@objc
class YAPDBReactionFinderAdapter: NSObject, ReactionFinderAdapter {

    private let uniqueMessageId: String

    init(uniqueMessageId: String) {
        self.uniqueMessageId = uniqueMessageId
    }

    func reaction(for reactor: SignalServiceAddress, transaction: YapDatabaseReadTransaction) -> OWSReaction? {
        if let reaction = reactionForUUID(reactor.uuid, transaction: transaction) {
            return reaction
        } else if let reaction = reactionForE164(reactor.phoneNumber, transaction: transaction) {
            return reaction
        } else {
            return nil
        }
    }

    private func reactionForUUID(_ uuid: UUID?, transaction: YapDatabaseReadTransaction) -> OWSReaction? {
        guard let uuidString = uuid?.uuidString else { return nil }

        guard let ext = transaction.ext(YAPDBReactionFinderAdapter.indexName) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(
            format: "WHERE %@ = \"%@\" AND %@ = \"%@\"",
            YAPDBReactionFinderAdapter.uuidKey,
            uuidString,
            YAPDBReactionFinderAdapter.uniqueMessageIdKey,
            uniqueMessageId
        )
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedReaction: OWSReaction?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let reaction = object as? OWSReaction else { return }
            matchedReaction = reaction
            stop.pointee = true
        }

        return matchedReaction
    }

    private func reactionForE164(_ e164: String?, transaction: YapDatabaseReadTransaction) -> OWSReaction? {
        guard let e164 = e164 else { return nil }

        guard let ext = transaction.ext(YAPDBReactionFinderAdapter.indexName) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(
            format: "WHERE %@ = \"%@\" AND %@ = \"%@\"",
            YAPDBReactionFinderAdapter.e164Key,
            e164,
            YAPDBReactionFinderAdapter.uniqueMessageIdKey,
            uniqueMessageId
        )
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedReaction: OWSReaction?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let reaction = object as? OWSReaction else { return }
            matchedReaction = reaction
            stop.pointee = true
        }

        return matchedReaction
    }

    func reactors(for emoji: String, transaction: YapDatabaseReadTransaction) -> [SignalServiceAddress]? {
        guard let ext = transaction.ext(YAPDBReactionFinderAdapter.indexName) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(
            format: "WHERE %@ = \"%@\" AND %@ = \"%@\"",
            YAPDBReactionFinderAdapter.emojiKey,
            emoji,
            YAPDBReactionFinderAdapter.uniqueMessageIdKey,
            uniqueMessageId
        )
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var reactors = [SignalServiceAddress]()

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, _ in
            guard let reaction = object as? OWSReaction else { return }
            reactors.append(reaction.reactor)
        }

        return reactors.isEmpty ? nil : reactors
    }

    func emojiCounts(transaction: YapDatabaseReadTransaction) -> [(emoji: String, count: Int)]? {
        var countMap = [String: Int]()

        enumerateReactions(transaction: transaction) { reaction, _ in
            var count = countMap[reaction.emoji] ?? 0
            count += 1
            countMap[reaction.emoji] = count
        }

        guard !countMap.isEmpty else { return nil }

        return countMap.map { (emoji: $0.key, count: $0.value) }.sorted { lhs, rhs in
            return lhs.count > rhs.count
        }
    }

    func existsReaction(transaction: YapDatabaseReadTransaction) -> Bool {
        var hasReaction = false

        enumerateReactions(transaction: transaction) { _, stop in
            hasReaction = true
            stop.pointee = true
        }

        return hasReaction
    }

    func enumerateReactions(
        transaction: YapDatabaseReadTransaction,
        block: @escaping (OWSReaction, UnsafeMutablePointer<ObjCBool>
    ) -> Void) {
        guard let ext = transaction.ext(YAPDBReactionFinderAdapter.indexName) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return
        }

        let queryFormat = String(
            format: "WHERE %@ = \"%@\"",
            YAPDBReactionFinderAdapter.uniqueMessageIdKey,
            uniqueMessageId
        )
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let reaction = object as? OWSReaction else { return }
            block(reaction, stop)
        }
    }

    func allUniqueIds(transaction: YapDatabaseReadTransaction) -> [String]? {
        var uniqueIds = [String]()
        enumerateReactions(transaction: transaction) { reaction, _ in
            uniqueIds.append(reaction.uniqueId)
        }
        return uniqueIds.isEmpty ? nil : uniqueIds
    }

    func deleteAllReactions(transaction: YapDatabaseReadWriteTransaction) throws {
        enumerateReactions(transaction: transaction) { reaction, _ in
            reaction.anyRemove(transaction: transaction.asAnyWrite)
        }
    }

    static func deleteReactions(with uniqueIds: [String], transaction: YapDatabaseReadWriteTransaction) throws {
        for uniqueId in uniqueIds {
            guard let reaction = OWSReaction.anyFetch(uniqueId: uniqueId, transaction: transaction.asAnyRead) else {
                owsFailDebug("Tried to remove uniqueId that doesn't exist: \(uniqueId)")
                continue
            }
            reaction.anyRemove(transaction: transaction.asAnyWrite)
        }
    }

    // MARK: -

    private static let uniqueMessageIdKey = "uniqueMessageIdKey"
    private static let uuidKey = "uuidKey"
    private static let e164Key = "e164Key"
    private static let emojiKey = "emojiKey"

    private static let indexName = "index_on_uniqueMessageId_and_reactor_and_emoji"

    @objc
    static func asyncRegisterDatabaseExtensions(_ storage: OWSStorage) {
        storage.asyncRegister(indexExtension(), withName: indexName)
    }

    private static func indexExtension() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(uuidKey, with: .text)
        setup.addColumn(e164Key, with: .text)
        setup.addColumn(emojiKey, with: .text)
        setup.addColumn(uniqueMessageIdKey, with: .text)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let indexableObject = object as? OWSReaction else {
                return
            }

            dict[uuidKey] = indexableObject.reactorUUID
            dict[e164Key] = indexableObject.reactorE164
            dict[emojiKey] = indexableObject.emoji
            dict[uniqueMessageIdKey] = indexableObject.uniqueMessageId
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "1")
    }
}

// MARK: -

struct GRDBReactionFinderAdapter: ReactionFinderAdapter {

    let uniqueMessageId: String

    init(uniqueMessageId: String) {
        self.uniqueMessageId = uniqueMessageId
    }

    func reaction(for reactor: SignalServiceAddress, transaction: GRDBReadTransaction) -> OWSReaction? {
        if let reaction = reactionForUUID(reactor.uuid, transaction: transaction) {
            return reaction
        } else if let reaction = reactionForE164(reactor.phoneNumber, transaction: transaction) {
            return reaction
        } else {
            return nil
        }
    }

    private func reactionForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> OWSReaction? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = """
            SELECT * FROM \(ReactionRecord.databaseTableName)
            WHERE \(reactionColumn: .uniqueMessageId) = ?
            AND \(reactionColumn: .reactorUUID) = ?
        """
        return OWSReaction.grdbFetchOne(sql: sql, arguments: [uniqueMessageId, uuidString], transaction: transaction)
    }

    private func reactionForE164(_ e164: String?, transaction: GRDBReadTransaction) -> OWSReaction? {
        guard let e164 = e164 else { return nil }
        let sql = """
            SELECT * FROM \(ReactionRecord.databaseTableName)
            WHERE \(reactionColumn: .uniqueMessageId) = ?
            AND \(reactionColumn: .reactorE164) = ?
        """
        return OWSReaction.grdbFetchOne(sql: sql, arguments: [uniqueMessageId, e164], transaction: transaction)
    }

    func reactors(for emoji: String, transaction: GRDBReadTransaction) -> [SignalServiceAddress]? {
        let sql = """
            SELECT * FROM \(ReactionRecord.databaseTableName)
            WHERE \(reactionColumn: .uniqueMessageId) = ?
            AND \(reactionColumn: .emoji) = ?
        """
        let cursor = OWSReaction.grdbFetchCursor(sql: sql, arguments: [uniqueMessageId, emoji], transaction: transaction)

        var reactors = [SignalServiceAddress]()

        do {
            while let reaction = try cursor.next() {
                reactors.append(reaction.reactor)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }

        return reactors.isEmpty ? nil : reactors
    }

    func emojiCounts(transaction: GRDBReadTransaction) -> [(emoji: String, count: Int)]? {
        let sql = """
            SELECT COUNT(*) as count, \(reactionColumn: .emoji)
            FROM \(ReactionRecord.databaseTableName)
            WHERE \(reactionColumn: .uniqueMessageId) = ?
            GROUP BY \(reactionColumn: .emoji)
            ORDER BY count DESC
        """
        let sqlRequest = SQLRequest<Void>(sql: sql, arguments: [uniqueMessageId], cached: true)

        do {
            let rows = try Row.fetchAll(transaction.database, sqlRequest)
            return rows.map { (emoji: $0[1], count: $0[0]) }
        } catch {
            owsFailDebug("unexpected error \(error)")
            return nil
        }
    }

    func existsReaction(transaction: GRDBReadTransaction) -> Bool {
        let sql = """
            SELECT EXISTS(
                SELECT 1
                FROM \(ReactionRecord.databaseTableName)
                WHERE \(reactionColumn: .uniqueMessageId) = ?
                LIMIT 1
            )
        """
        let arguments: StatementArguments = [uniqueMessageId]
        return (try? Bool.fetchOne(transaction.database, sql: sql, arguments: arguments)) ?? false
    }

    func enumerateReactions(
        transaction: GRDBReadTransaction,
        block: @escaping (OWSReaction, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let sql = """
            SELECT *
            FROM \(ReactionRecord.databaseTableName)
            WHERE \(reactionColumn: .uniqueMessageId) = ?
        """
        let cursor = OWSReaction.grdbFetchCursor(sql: sql, arguments: [uniqueMessageId], transaction: transaction)

        do {
            while let reaction = try cursor.next() {
                var stop: ObjCBool = false
                block(reaction, &stop)
                if stop.boolValue { break }
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }
    }

    func allUniqueIds(transaction: GRDBReadTransaction) -> [String]? {
        let sql = """
            SELECT \(reactionColumn: .uniqueId)
            FROM \(ReactionRecord.databaseTableName)
            WHERE \(reactionColumn: .uniqueMessageId) = ?
        """
        let sqlRequest = SQLRequest<Void>(sql: sql, arguments: [uniqueMessageId], cached: true)

        do {
            let rows = try Row.fetchAll(transaction.database, sqlRequest)
            return rows.map { $0[0] }
        } catch {
            owsFailDebug("unexpected error \(error)")
            return nil
        }
    }

    func deleteAllReactions(transaction: GRDBWriteTransaction) throws {
        let sql = """
            DELETE FROM \(ReactionRecord.databaseTableName)
            WHERE \(reactionColumn: .uniqueMessageId) = ?
        """
        try transaction.database.execute(sql: sql, arguments: [uniqueMessageId])
    }

    static func deleteReactions(with uniqueIds: [String], transaction: GRDBWriteTransaction) throws {
        let sql = """
            DELETE FROM \(ReactionRecord.databaseTableName)
            WHERE \(reactionColumn: .uniqueId) IN (?)
        """
        try transaction.database.execute(sql: sql, arguments: [uniqueIds.joined(separator: ", ")])
    }
}
