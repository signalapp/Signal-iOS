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

        try storage.write { grdbTransaction in
            var threadFinder: LegacyUnorderedFinder<TSThread>!
            var interactionFinder: LegacyInteractionFinder!
            var jobRecordFinder: LegacyJobRecordFinder!
            dbReadConnection.read { transaction in
                threadFinder = LegacyUnorderedFinder<TSThread>(transaction: transaction)
                interactionFinder = LegacyInteractionFinder(transaction: transaction)
                jobRecordFinder = LegacyJobRecordFinder(transaction: transaction)
            }

            try! self.migrateJobRecords(jobRecordFinder: jobRecordFinder, transaction: grdbTransaction)
            try! self.migrateThreads(finder: threadFinder, transaction: grdbTransaction)
            try! self.migrateInteractions(interactionFinder: interactionFinder, transaction: grdbTransaction)

            SDSDatabaseStorage.shouldLogDBQueries = true
        }
    }

    private func migrateJobRecords(jobRecordFinder: LegacyJobRecordFinder, transaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate SSKJobRecord", memorySamplerRatio: 0.02) { memorySampler in
            var recordCount = 0
            try jobRecordFinder.enumerateJobRecords { legacyRecord in
                recordCount += 1
                try SDSSerialization.insert(entity: legacyRecord, database: transaction.database)
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }

    private func migrateThreads(finder: LegacyUnorderedFinder<TSThread>, transaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate TSThread", memorySamplerRatio: 0.02) { memorySampler in
            var recordCount = 0
            try finder.enumerateRecords { legacyRecord in
                recordCount += 1
                try SDSSerialization.insert(entity: legacyRecord, database: transaction.database)
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }

    private func migrateInteractions(interactionFinder: LegacyInteractionFinder, transaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate Interactions", memorySamplerRatio: 0.001) { memorySampler in
            var recordCount = 0
            try interactionFinder.enumerateInteractions { legacyInteraction in
                try SDSSerialization.insert(entity: legacyInteraction, database: transaction.database)
                recordCount += 1
                if (recordCount % 500 == 0) {
                    Logger.debug("saved \(recordCount) interactions")
                }
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }
}

private class LegacyUnorderedFinder<RecordType> where RecordType: TSYapDatabaseObject {
    // HACK: normally we don't want to retain transactions, as it allows them to escape their
    // closure. This is a work around since YapDB transactions want to be on their own sync queue
    // while GRDB also wants to be on their own sync queue, so nesting a YapDB transaction from
    // one DB inside a GRDB transaction on another DB is currently not possible.
    let transaction: YapDatabaseReadTransaction

    init(transaction: YapDatabaseReadTransaction) {
        self.transaction = transaction
    }

    public func enumerateRecords(block: @escaping (RecordType) throws -> Void ) throws {
        try transaction.enumerateKeysAndObjects(inCollection: RecordType.collection()) { (_: String, yapObject: Any, _: UnsafeMutablePointer<ObjCBool>) throws -> Void in
            guard let thread = yapObject as? RecordType else {
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
    // one DB inside a GRDB transaction on another DB is currently not possible.
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

private class LegacyJobRecordFinder {

    let extensionName = YAPDBJobRecordFinder.dbExtensionName

    // HACK: normally we don't want to retain transactions, as it allows them to escape their
    // closure. This is a work around since YapDB transactions want to be on their own sync queue
    // while GRDB also wants to be on their own sync queue, so nesting a YapDB transaction from
    // one DB inside a GRDB transaction on another DB is currently not possible.
    var ext: YapDatabaseSecondaryIndexTransaction
    init(transaction: YapDatabaseReadTransaction) {
        self.ext = transaction.extension(extensionName) as! YapDatabaseSecondaryIndexTransaction
    }

    public func enumerateJobRecords(block: @escaping (SSKJobRecord) throws -> Void) throws {
        try enumerateJobRecords(ext: ext, block: block)
    }

    func enumerateJobRecords(ext: YapDatabaseSecondaryIndexTransaction, block: @escaping (SSKJobRecord) throws -> Void) throws {
        let queryFormat = String(format: "ORDER BY %@", "sortId")
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var errorToRaise: Error?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stopPtr in
            do {
                guard let jobRecord = object as? SSKJobRecord else {
                    owsFailDebug("expecting jobRecord but found: \(object)")
                    return
                }
                try block(jobRecord)
            } catch {
                owsFailDebug("error: \(error)")
                errorToRaise = error
                stopPtr.pointee = true
            }
        }

        if let errorToRaise = errorToRaise {
            throw errorToRaise
        }
    }
}
