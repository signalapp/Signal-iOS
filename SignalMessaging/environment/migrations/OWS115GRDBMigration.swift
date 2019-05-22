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
            var sessionStoreFinder: LegacyKeyValueFinder<[Int: SessionRecord]>!
            var preKeyStoreFinder: LegacyKeyValueFinder<PreKeyRecord>!
            var preKeyMetadataFinder: LegacyKeyValueFinder<Any>!
            var signedPreKeyStoreFinder: LegacyKeyValueFinder<SignedPreKeyRecord>!
            var signedPreKeyMetadataFinder: LegacyKeyValueFinder<Any>!

            var ownIdentityFinder: LegacyKeyValueFinder<ECKeyPair>!
            var queuedVerificationStateSyncMessagesFinder: LegacyKeyValueFinder<String>!
            var tsAccountManagerFinder: LegacyKeyValueFinder<Any>!

            dbReadConnection.read { yapTransaction in
                jobRecordFinder = LegacyJobRecordFinder(transaction: yapTransaction)
                interactionFinder = LegacyInteractionFinder(transaction: yapTransaction)
                decryptJobFinder = LegacyUnorderedFinder(transaction: yapTransaction)

                // protocol store finders
                preKeyStoreFinder = LegacyKeyValueFinder(store: self.preKeyStore.keyStore, transaction: yapTransaction)
                preKeyMetadataFinder = LegacyKeyValueFinder(store: self.preKeyStore.metadataStore, transaction: yapTransaction)

                signedPreKeyStoreFinder = LegacyKeyValueFinder(store: self.signedPreKeyStore.keyStore, transaction: yapTransaction)
                signedPreKeyMetadataFinder = LegacyKeyValueFinder(store: self.signedPreKeyStore.metadataStore, transaction: yapTransaction)

                ownIdentityFinder = LegacyKeyValueFinder(store: self.identityManager.ownIdentityKeyValueStore, transaction: yapTransaction)

                sessionStoreFinder = LegacyKeyValueFinder(store: self.sessionStore.keyValueStore, transaction: yapTransaction)
                queuedVerificationStateSyncMessagesFinder = LegacyKeyValueFinder(store: self.identityManager.queuedVerificationStateSyncMessagesKeyValueStore, transaction: yapTransaction)
                tsAccountManagerFinder = LegacyKeyValueFinder(store: self.tsAccountManager.keyValueStore, transaction: yapTransaction)

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

            // migrate keyvalue stores
            try! self.migrateKeyValueStore(label: "sessionStore", finder: sessionStoreFinder, memorySamplerRatio: 1.0, transaction: grdbTransaction)

            try! self.migrateKeyValueStore(label: "ownIdentity", finder: ownIdentityFinder, memorySamplerRatio: 1.0, transaction: grdbTransaction)
            try! self.migrateKeyValueStore(label: "queuedVerificationStateSyncMessages", finder: queuedVerificationStateSyncMessagesFinder, memorySamplerRatio: 0.3, transaction: grdbTransaction)
            try! self.migrateKeyValueStore(label: "tsAccountManager", finder: tsAccountManagerFinder, memorySamplerRatio: 0.3, transaction: grdbTransaction)

            try! self.migrateKeyValueStore(label: "preKey Store", finder: preKeyStoreFinder, memorySamplerRatio: 0.3, transaction: grdbTransaction)
            try! self.migrateKeyValueStore(label: "preKey Metadata", finder: preKeyMetadataFinder, memorySamplerRatio: 0.3, transaction: grdbTransaction)
            try! self.migrateKeyValueStore(label: "signedPreKey Store", finder: signedPreKeyStoreFinder, memorySamplerRatio: 0.3, transaction: grdbTransaction)
            try! self.migrateKeyValueStore(label: "signedPreKey Metadata", finder: signedPreKeyMetadataFinder, memorySamplerRatio: 0.3, transaction: grdbTransaction)

            // unordered migrations
            try! self.migrateUnorderedRecords(label: "threads", finder: threadFinder, memorySamplerRatio: 0.2, transaction: grdbTransaction)
            try! self.migrateUnorderedRecords(label: "attachments", finder: attachmentFinder, memorySamplerRatio: 0.003, transaction: grdbTransaction)
            try! self.migrateUnorderedRecords(label: "contentJob", finder: contentJobFinder, memorySamplerRatio: 0.05, transaction: grdbTransaction)
            try! self.migrateUnorderedRecords(label: "recipientIdentities", finder: recipientIdentityFinder, memorySamplerRatio: 0.02, transaction: grdbTransaction)

            // Logging queries is helpful for normal debugging, but expensive during a migration
            SDSDatabaseStorage.shouldLogDBQueries = true
        }
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

    private func migrateKeyValueStore<T>(label: String, finder: LegacyKeyValueFinder<T>, memorySamplerRatio: Float, transaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate \(label)", memorySamplerRatio: memorySamplerRatio) { memorySampler in
            var recordCount = 0
            try finder.enumerateLegacyKeysAndObjects { legacyKey, legacyObject in
                recordCount += 1
                finder.store.setObject(legacyObject, key: legacyKey, transaction: transaction.asAnyWrite)
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

private class LegacyKeyValueFinder<T>: LegacyObjectFinder<T> {
    let store: SDSKeyValueStore

    init(store: SDSKeyValueStore, transaction: YapDatabaseReadTransaction) {
        self.store = store
        super.init(collection: store.collection, transaction: transaction)
    }
}

private class LegacyUnorderedFinder<RecordType>: LegacyObjectFinder<RecordType> where RecordType: TSYapDatabaseObject {
    init(transaction: YapDatabaseReadTransaction) {
        super.init(collection: RecordType.collection(), transaction: transaction)
    }
}

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
