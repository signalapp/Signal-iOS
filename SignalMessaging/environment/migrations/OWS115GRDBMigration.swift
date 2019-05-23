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

// MARK: -

extension OWS115GRDBMigration {

    // MARK: - Dependencies

    var storage: GRDBDatabaseStorageAdapter {
        return SDSDatabaseStorage.shared.grdbStorage
    }

    var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    var identityManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    var sessionStore: SSKSessionStore {
        return SSKEnvironment.shared.sessionStore
    }

    var preKeyStore: SSKPreKeyStore {
        return SSKEnvironment.shared.preKeyStore
    }

    var signedPreKeyStore: SSKSignedPreKeyStore {
        return SSKEnvironment.shared.signedPreKeyStore
    }

    // MARK: -

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
            // Custom Finders - For more complex cases
            var jobRecordFinder: LegacyJobRecordFinder!
            var interactionFinder: LegacyInteractionFinder!
            var decryptJobFinder: LegacyUnorderedFinder<OWSMessageDecryptJob>!

            // LegacyUnorderedFinder - These are simple to migrate
            var attachmentFinder: LegacyUnorderedFinder<TSAttachment>!
            var contentJobFinder: LegacyUnorderedFinder<OWSMessageContentJob>!
            var recipientIdentityFinder: LegacyUnorderedFinder<OWSRecipientIdentity>!
            var threadFinder: LegacyUnorderedFinder<TSThread>!

            // KeyValue Finders
            var migrators = [GRDBMigrator]()

            dbReadConnection.read { yapTransaction in
                jobRecordFinder = LegacyJobRecordFinder(transaction: yapTransaction)
                interactionFinder = LegacyInteractionFinder(transaction: yapTransaction)
                decryptJobFinder = LegacyUnorderedFinder(transaction: yapTransaction)

                migrators += self.allKeyValueMigrators(yapTransaction: yapTransaction)

                // unordered finders
                attachmentFinder = LegacyUnorderedFinder(transaction: yapTransaction)
                contentJobFinder = LegacyUnorderedFinder(transaction: yapTransaction)
                recipientIdentityFinder = LegacyUnorderedFinder(transaction: yapTransaction)
                threadFinder = LegacyUnorderedFinder(transaction: yapTransaction)
            }

            // custom migrations
            try! self.migrateJobRecords(jobRecordFinder: jobRecordFinder, transaction: grdbTransaction)
            try! self.migrateInteractions(interactionFinder: interactionFinder, transaction: grdbTransaction)
            try! self.migrateMappedCollectionObjects(label: "DecryptJobs", finder: decryptJobFinder, memorySamplerRatio: 0.1, transaction: grdbTransaction) { (legacyJob: OWSMessageDecryptJob) -> SSKMessageDecryptJobRecord in

                // migrate any job records from the one-off decrypt job queue to a record for the new generic durable job queue
                return SSKMessageDecryptJobRecord(envelopeData: legacyJob.envelopeData, label: SSKMessageDecryptJobQueue.jobRecordLabel)
            }

            // Migrate migrators
            for migrator in migrators {
                try! migrator.migrate(grdbTransaction: grdbTransaction)
            }

            // unordered migrations
            try! self.migrateUnorderedRecords(label: "threads", finder: threadFinder, memorySamplerRatio: 0.2, transaction: grdbTransaction)
            try! self.migrateUnorderedRecords(label: "attachments", finder: attachmentFinder, memorySamplerRatio: 0.003, transaction: grdbTransaction)
            try! self.migrateUnorderedRecords(label: "contentJob", finder: contentJobFinder, memorySamplerRatio: 0.05, transaction: grdbTransaction)
            try! self.migrateUnorderedRecords(label: "recipientIdentities", finder: recipientIdentityFinder, memorySamplerRatio: 0.02, transaction: grdbTransaction)

            // Logging queries is helpful for normal debugging, but expensive during a migration
            SDSDatabaseStorage.shouldLogDBQueries = true
        }
    }

    private func allKeyValueMigrators(yapTransaction: YapDatabaseReadTransaction) -> [GRDBMigrator] {
        return [
            GRDBKeyValueStoreMigrator<PreKeyRecord>(label: "preKey Store", keyStore: preKeyStore.keyStore, yapTransaction: yapTransaction, memorySamplerRatio: 0.3),
            GRDBKeyValueStoreMigrator<Any>(label: "preKey Metadata", keyStore: preKeyStore.metadataStore, yapTransaction: yapTransaction, memorySamplerRatio: 0.3),

            GRDBKeyValueStoreMigrator<SignedPreKeyRecord>(label: "signedPreKey Store", keyStore: signedPreKeyStore.keyStore, yapTransaction: yapTransaction, memorySamplerRatio: 0.3),
            GRDBKeyValueStoreMigrator<Any>(label: "signedPreKey Metadata", keyStore: signedPreKeyStore.metadataStore, yapTransaction: yapTransaction, memorySamplerRatio: 0.3),

            GRDBKeyValueStoreMigrator<ECKeyPair>(label: "ownIdentity", keyStore: identityManager.ownIdentityKeyValueStore, yapTransaction: yapTransaction, memorySamplerRatio: 1.0),

            GRDBKeyValueStoreMigrator<[Int: SessionRecord]>(label: "sessionStore", keyStore: sessionStore.keyValueStore, yapTransaction: yapTransaction, memorySamplerRatio: 1.0),

            GRDBKeyValueStoreMigrator<String>(label: "queuedVerificationStateSyncMessages", keyStore: identityManager.queuedVerificationStateSyncMessagesKeyValueStore, yapTransaction: yapTransaction, memorySamplerRatio: 0.3),

            GRDBKeyValueStoreMigrator<Any>(label: "tsAccountManager", keyStore: tsAccountManager.keyValueStore, yapTransaction: yapTransaction, memorySamplerRatio: 0.3),

            GRDBKeyValueStoreMigrator<Any>(label: "AppPreferences", keyStore: AppPreferences.store, yapTransaction: yapTransaction, memorySamplerRatio: 1.0),
            GRDBKeyValueStoreMigrator<Any>(label: "SSKPreferences", keyStore: SSKPreferences.store, yapTransaction: yapTransaction, memorySamplerRatio: 1.0),
            GRDBKeyValueStoreMigrator<Any>(label: "StickerManager.store", keyStore: StickerManager.store, yapTransaction: yapTransaction, memorySamplerRatio: 1.0),
            GRDBKeyValueStoreMigrator<Any>(label: "StickerManager.emojiMapStore", keyStore: StickerManager.emojiMapStore, yapTransaction: yapTransaction, memorySamplerRatio: 1.0)
            ]
    }

    private func migrateUnorderedRecords<T>(label: String, finder: LegacyUnorderedFinder<T>, memorySamplerRatio: Float, transaction: GRDBWriteTransaction) throws where T: SDSModel {
        try Bench(title: "Migrate \(label)", memorySamplerRatio: memorySamplerRatio) { memorySampler in
            var recordCount = 0
            try finder.enumerateLegacyObjects { legacyRecord in
                recordCount += 1
                legacyRecord.anyInsert(transaction: transaction.asAnyWrite)
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }

    private func migrateMappedCollectionObjects<SourceType, DestinationType>(label: String,
                                                                             finder: LegacyObjectFinder<SourceType>,
                                                                             memorySamplerRatio: Float,
                                                                             transaction: GRDBWriteTransaction,
                                                                             migrateObject: @escaping (SourceType) -> DestinationType) throws where DestinationType: SDSModel {

        try Bench(title: "Migrate \(SourceType.self)", memorySamplerRatio: memorySamplerRatio) { memorySampler in
            var recordCount = 0
            try finder.enumerateLegacyObjects { legacyObject in
                recordCount += 1
                let newObject = migrateObject(legacyObject)
                newObject.anyInsert(transaction: transaction.asAnyWrite)
                memorySampler.sample()
            }
            Logger.info("Migrate \(SourceType.self) completed with recordCount: \(recordCount)")
        }
    }

    private func migrateJobRecords(jobRecordFinder: LegacyJobRecordFinder, transaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate SSKJobRecord", memorySamplerRatio: 0.02) { memorySampler in
            var recordCount = 0
            try jobRecordFinder.enumerateJobRecords { legacyRecord in
                recordCount += 1
                legacyRecord.anyInsert(transaction: transaction.asAnyWrite)
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }

    private func migrateInteractions(interactionFinder: LegacyInteractionFinder, transaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate Interactions", memorySamplerRatio: 0.001) { memorySampler in
            var recordCount = 0
            try interactionFinder.enumerateInteractions { legacyInteraction in
                legacyInteraction.anyInsert(transaction: transaction.asAnyWrite)
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

// MARK: -

private class LegacyObjectFinder<T> {
    let collection: String

    // HACK: normally we don't want to retain transactions, as it allows them to escape their
    // closure. This is a work around since YapDB transactions want to be on their own sync queue
    // while GRDB also wants to be on their own sync queue, so nesting a YapDB transaction from
    // one DB inside a GRDB transaction on another DB is currently not possible.
    let transaction: YapDatabaseReadTransaction

    init(collection: String, transaction: YapDatabaseReadTransaction) {
        self.collection = collection
        self.transaction = transaction
    }

    public func enumerateLegacyKeysAndObjects(block: @escaping (String, T) throws -> Void ) throws {
        try transaction.enumerateKeysAndObjects(inCollection: collection) { (collectionKey: String, collectionObj: Any, _: UnsafeMutablePointer<ObjCBool>) throws -> Void in
            guard let legacyObj = collectionObj as? T else {
                owsFailDebug("unexpected collectionObj: \(type(of: collectionObj)) collectionKey: \(collectionKey)")
                return
            }
            try block(collectionKey, legacyObj)
        }
    }

    public func enumerateLegacyObjects(block: @escaping (T) throws -> Void ) throws {
        try transaction.enumerateKeysAndObjects(inCollection: collection) { (_: String, collectionObj: Any, _: UnsafeMutablePointer<ObjCBool>) throws -> Void in
            guard let legacyObj = collectionObj as? T else {
                owsFailDebug("unexpected collectionObj: \(type(of: collectionObj))")
                return
            }
            try block(legacyObj)
        }
    }
}

// MARK: -

private class LegacyKeyValueFinder<T>: LegacyObjectFinder<T> {
    let store: SDSKeyValueStore

    init(store: SDSKeyValueStore, transaction: YapDatabaseReadTransaction) {
        self.store = store
        super.init(collection: store.collection, transaction: transaction)
    }
}

// MARK: -

private class LegacyUnorderedFinder<RecordType>: LegacyObjectFinder<RecordType> where RecordType: TSYapDatabaseObject {
    init(transaction: YapDatabaseReadTransaction) {
        super.init(collection: RecordType.collection(), transaction: transaction)
    }
}

// MARK: -

private class LegacyInteractionFinder {
    let extensionName = TSMessageDatabaseViewExtensionName

    // HACK: normally we don't want to retain transactions, as it allows them to escape their
    // closure. This is a work around since YapDB transactions want to be on their own sync queue
    // while GRDB also wants to be on their own sync queue, so nesting a YapDB transaction from
    // one DB inside a GRDB transaction on another DB is currently not possible.
    let ext: YapDatabaseAutoViewTransaction
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

// MARK: -

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

// MARK: -

private protocol GRDBMigrator {
    func migrate(grdbTransaction: GRDBWriteTransaction) throws
}

// MARK: -

private class GRDBKeyValueStoreMigrator<T> : GRDBMigrator {
    private let label: String
    private let finder: LegacyKeyValueFinder<T>
    private let memorySamplerRatio: Float

    init(label: String, keyStore: SDSKeyValueStore, yapTransaction: YapDatabaseReadTransaction, memorySamplerRatio: Float) {
        self.label = label
        self.finder = LegacyKeyValueFinder(store: keyStore, transaction: yapTransaction)
        self.memorySamplerRatio = memorySamplerRatio
    }

    func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate \(label)", memorySamplerRatio: memorySamplerRatio) { memorySampler in
            var recordCount = 0
            try finder.enumerateLegacyKeysAndObjects { legacyKey, legacyObject in
                recordCount += 1
                self.finder.store.setObject(legacyObject, key: legacyKey, transaction: grdbTransaction.asAnyWrite)
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }
}
