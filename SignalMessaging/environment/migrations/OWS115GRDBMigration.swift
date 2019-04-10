//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

@objc
public class OWS115GRDBMigration: OWSDatabaseMigration {

    // Increment a similar constant for each migration.
    @objc
    class func migrationId() -> String {
        return "115"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")

        DispatchQueue.global().async {
            if FeatureFlags.useGRDB {
                Bench(title: "\(self.logTag)") {
                    try! self.run()
                }
            }
            completion()
        }
    }

    override public func save(with transaction: YapDatabaseReadWriteTransaction) {
        if FeatureFlags.grdbMigratesFreshDBEveryLaunch {
            // Do nothing so as to re-run every launch.
            // Useful while actively developing the migration.
            return
        } else {
            super.save(with: transaction)
        }
    }
}

extension OWS115GRDBMigration {

    // MARK: - Dependencies

    var storage: GRDBDatabaseStorageAdapter {
        return SDSDatabaseStorage.shared.grdbStorage
    }

    func run() throws {
        Logger.info("")

        // We can't nest YapTransactions in GRDB and vice-versa
        // each has their own serial-queue based concurrency model, which wants to be on
        // _their own_ serial queue.
        //
        // GRDB at least supports nesting multiple database transactions, but the _both_
        // have to be accessed via GRDB
        //
        // TODO: see if we can get reasonable perf by avoiding the nested transactions and
        // instead doing work in non-overlapping batches.
        let dbReadConnection = OWSPrimaryStorage.shared().newDatabaseConnection()
        dbReadConnection.beginLongLivedReadTransaction()

        try self.storage.pool.write { (modernDb: Database) in
            var threadFinder: LegacyThreadFinder!
            var interactionFinder: LegacyInteractionFinder!
            dbReadConnection.read { transaction in
                threadFinder = LegacyThreadFinder(transaction: transaction)
                interactionFinder = LegacyInteractionFinder(transaction: transaction)
            }

            try self.migrateThreads(threadFinder: threadFinder, modernDb: modernDb)
            try self.migrateInteractions(interactionFinder: interactionFinder, modernDb: modernDb)

            SDSDatabaseStorage.shouldLogDBQueries = true
        }
    }

    private func migrateInteractions(interactionFinder: LegacyInteractionFinder, modernDb: Database) throws {
        try Bench(title: "Migrate Interactions", memorySamplerRatio: 0.001) { memorySampler in
            var i = 0

            let cn = InteractionRecord.columnName
            let insertStatement = try modernDb.makeUpdateStatement(sql: """
                INSERT INTO interactions (
                    \(cn(.uniqueId)),
                    \(cn(.threadUniqueId)),
                    \(cn(.senderTimestamp)),
                    \(cn(.interactionType)),
                    \(cn(.messageBody))
                )
                VALUES (?, ?, ?, ?, ?)
                """)

            try interactionFinder.enumerateInteractions { legacyInteraction in
                i += 1
                let messageBody: String? = (legacyInteraction as? TSMessage)?.body
                insertStatement.unsafeSetArguments([legacyInteraction.uniqueId,
                                                    legacyInteraction.uniqueThreadId,
                                                    legacyInteraction.timestamp,
                                                    InteractionRecordType(owsInteractionType: legacyInteraction.interactionType()),
                                                    messageBody])
                try insertStatement.execute()
                if (i % 500 == 0) {
                    Logger.debug("saved \(i) interactions")
                }
                memorySampler.sample()
            }
        }
    }

    private func migrateThreads(threadFinder: LegacyThreadFinder, modernDb: Database) throws {
        try Bench(title: "Migrate Threads", memorySamplerRatio: 0.02) { memorySampler in
                let cn = ThreadRecord.columnName
                let insertStatement = try modernDb.makeUpdateStatement(sql: """
                    INSERT INTO threads (
                        \(cn(.uniqueId)),
                        \(cn(.shouldBeVisible)),
                        \(cn(.creationDate)),
                        \(cn(.threadType))
                    )
                    VALUES (?, ?, ?, ?)
                    """)

                try threadFinder.enumerateThreads { legacyThread in
                    guard let uniqueId = legacyThread.uniqueId else {
                        owsFailDebug("uniqueId was unexpectedly nil")
                        throw OWSErrorMakeAssertionError("thread.uniqueId was unexpectedly nil")
                    }

                    let threadType: ThreadRecordType = legacyThread.isGroupThread() ? .group : .contact
                    insertStatement.unsafeSetArguments([uniqueId,
                                                        legacyThread.shouldThreadBeVisible,
                                                        legacyThread.creationDate,
                                                        threadType])
                    try insertStatement.execute()
                    memorySampler.sample()
            }
        }
    }

}

private class LegacyThreadFinder {
    // HACK: normally we don't want to retain transactions, as it allows them to escape their
    // closure. This is a work around since YapDB transactions want to be on their own sync queue
    // while GRDB also wants to be on their own sync queue, so nesting a YapDB transaction from
    // on DB inside a GRDB transaction on another DB is currently not possible.
    var transaction: YapDatabaseReadTransaction
    init(transaction: YapDatabaseReadTransaction) {
        self.transaction = transaction
    }

    public func enumerateThreads(block: @escaping (TSThread) throws -> Void ) throws {
        try transaction.enumerateKeysAndObjects(inCollection: TSThread.collection()) { (_: String, yapObject: Any, _: UnsafeMutablePointer<ObjCBool>) throws -> Void in
            guard let thread = yapObject as? TSThread else {
                owsFailDebug("unexpected yapObject: \(type(of: yapObject))")
                return
            }
            try block(thread)
        }
    }

}

private class LegacyInteractionFinder {
    let extensionName = TSMessageDatabaseViewExtensionName

    // HACK: normally we don't want to retain transactions, as it allows them to escape their
    // closure. This is a work around since YapDB transactions want to be on their own sync queue
    // while GRDB also wants to be on their own sync queue, so nesting a YapDB transaction from
    // on DB inside a GRDB transaction on another DB is currently not possible.
    var ext: YapDatabaseAutoViewTransaction
    init(transaction: YapDatabaseReadTransaction) {
        self.ext = transaction.extension(extensionName) as! YapDatabaseAutoViewTransaction
    }

    func ext(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseAutoViewTransaction {
        return transaction.extension(extensionName) as! YapDatabaseAutoViewTransaction
    }

    public func enumerateInteractions(transaction: YapDatabaseReadTransaction, block: @escaping (TSInteraction) throws -> Void ) throws {
        try enumerateInteractions(transaction: ext(transaction), block: block)
    }

    public func enumerateInteractions(block: @escaping (TSInteraction) throws -> Void) throws {
        try enumerateInteractions(transaction: ext, block: block)
    }

    func enumerateInteractions(transaction: YapDatabaseAutoViewTransaction, block: @escaping (TSInteraction) throws -> Void) throws {
        var errorToRaise: Error?
        transaction.enumerateGroups { groupId, stopPtr in
            autoreleasepool {
                transaction.enumerateKeysAndObjects(inGroup: groupId) { (_, _, object, _, stopPtr) in
                    do {
                        guard let interaction = object as? TSInteraction else {
                            owsFailDebug("unexpected object: \(type(of: object))")
                            return
                        }

                        try block(interaction)
                    } catch {
                        owsFailDebug("error: \(error)")
                        errorToRaise = error
                        stopPtr.pointee = true
                    }
                }
            }
        }

        if let errorToRaise = errorToRaise {
            throw errorToRaise
        }
    }
}
