//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalServiceKit

@objc
public class YDBToGRDBMigration: NSObject {

    // MARK: - Other key stores

    // This migration class resides in SignalMessaging. It ensures that we
    // migrate an kv stores in SignalMessaging or its dependency SSK.
    //
    // However it doesn't know about any key-value stores defined in the
    // Signal (or hypothetically the SignalShareExtension) target(s).
    // So the migration logic needs to be informed of those stores.
    private static var otherKeyStores = [String: SDSKeyValueStore]()

    @objc
    public class func add(keyStore: SDSKeyValueStore,
                          label: String) {
        AssertIsOnMainThread()

        guard otherKeyStores[label] == nil else {
            owsFailDebug("Keystore added twice.")
            return
        }
        otherKeyStores[label] = keyStore
    }
}

// MARK: -

@objc
public class GRDBMigratorGroup: NSObject {
    public typealias MigratorBlock = (YapDatabaseReadTransaction) -> [GRDBMigrator]

    private let block: MigratorBlock

    @objc
    public required init(block: @escaping MigratorBlock) {
        self.block = block
    }

    func migrators(ydbTransaction: YapDatabaseReadTransaction) -> [GRDBMigrator] {
        return block(ydbTransaction)
    }
}

// MARK: -

extension YDBToGRDBMigration {

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

    var environment: Environment {
        return Environment.shared
    }

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    var typingIndicators: TypingIndicators {
        return SSKEnvironment.shared.typingIndicators
    }

    var udManager: OWSUDManager {
        return SSKEnvironment.shared.udManager
    }

    var signalService: OWSSignalService {
        return OWSSignalService.sharedInstance()
    }

    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    var blockingManager: OWSBlockingManager {
        return .shared()
    }

    private var primaryStorage: OWSPrimaryStorage? {
        return SSKEnvironment.shared.primaryStorage
    }

    // MARK: -

    func run() throws {
        Logger.info("")

        // We migrate the data store contents in phases
        // or batches.  Each "group" defines the data to
        // migrate in a given batch.
        let migratorGroups = [
            // Migrate the key-value and unordered records first;
            // The later migrations may use these values in
            // "sneaky" transactions.
            GRDBMigratorGroup { ydbTransaction in
                return self.allKeyValueMigrators(ydbTransaction: ydbTransaction)
            },
            GRDBMigratorGroup { ydbTransaction in
                return self.allUnorderedRecordMigrators(ydbTransaction: ydbTransaction)
            },
            GRDBMigratorGroup { ydbTransaction in
                return [GRDBJobRecordMigrator(ydbTransaction: ydbTransaction)]
            },
            GRDBMigratorGroup { ydbTransaction in
                return [GRDBInteractionMigrator(ydbTransaction: ydbTransaction)]
            },
            GRDBMigratorGroup { ydbTransaction in
                return [GRDBDecryptJobMigrator(ydbTransaction: ydbTransaction)]
            }
        ]

        try self.migrate(migratorGroups: migratorGroups)
    }

    func migrate(migratorGroups: [GRDBMigratorGroup]) throws {
        assert(OWSStorage.isStorageReady())

        Logger.info("")

        // We can't nest ydbTransactions in GRDB and vice-versa
        // each has their own serial-queue based concurrency model, which wants to be on
        // _their own_ serial queue.
        //
        // GRDB at least supports nesting multiple database transactions, but the _both_
        // have to be accessed via GRDB
        //
        // TODO: see if we can get reasonable perf by avoiding the nested transactions and
        // instead doing work in non-overlapping batches.
        guard let primaryStorage = primaryStorage else {
            owsFail("Missing primaryStorage.")
        }
        let ydbReadConnection = primaryStorage.newDatabaseConnection()
        ydbReadConnection.beginLongLivedReadTransaction()

        for migratorGroup in migratorGroups {
            try migrate(migratorGroup: migratorGroup,
                        ydbReadConnection: ydbReadConnection)
        }
    }

    private func migrate(migratorGroup: GRDBMigratorGroup,
                         ydbReadConnection: YapDatabaseConnection) throws {
        Logger.info("")

        // Logging queries is helpful for normal debugging, but expensive during a migration
        SDSDatabaseStorage.shouldLogDBQueries = false

        try storage.write { grdbTransaction in
            // Instantiate the migrators.
            var migrators = [GRDBMigrator]()
            ydbReadConnection.read { ydbTransaction in
                migrators += migratorGroup.migrators(ydbTransaction: ydbTransaction)
            }

            // Migrate migrators.
            for migrator in migrators {
                try! migrator.migrate(grdbTransaction: grdbTransaction)
            }
        }

        SDSDatabaseStorage.shouldLogDBQueries = true
    }

    private func allKeyValueMigrators(ydbTransaction: YapDatabaseReadTransaction) -> [GRDBMigrator] {
        var result: [GRDBMigrator] = [
            GRDBKeyValueStoreMigrator<PreKeyRecord>(label: "preKey Store", keyStore: preKeyStore.keyStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.3),
            GRDBKeyValueStoreMigrator<Any>(label: "preKey Metadata", keyStore: preKeyStore.metadataStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.3),

            GRDBKeyValueStoreMigrator<SignedPreKeyRecord>(label: "signedPreKey Store", keyStore: signedPreKeyStore.keyStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.3),
            GRDBKeyValueStoreMigrator<Any>(label: "signedPreKey Metadata", keyStore: signedPreKeyStore.metadataStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.3),

            GRDBKeyValueStoreMigrator<ECKeyPair>(label: "ownIdentity", keyStore: identityManager.ownIdentityKeyValueStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),

            GRDBKeyValueStoreMigrator<[Int: SessionRecord]>(label: "sessionStore", keyStore: sessionStore.keyValueStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),

            GRDBKeyValueStoreMigrator<String>(label: "queuedVerificationStateSyncMessages", keyStore: identityManager.queuedVerificationStateSyncMessagesKeyValueStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.3),

            GRDBKeyValueStoreMigrator<Any>(label: "tsAccountManager", keyStore: tsAccountManager.keyValueStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.3),

            GRDBKeyValueStoreMigrator<Any>(label: "AppPreferences", keyStore: AppPreferences.store, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
            GRDBKeyValueStoreMigrator<Any>(label: "SSKPreferences", keyStore: SSKPreferences.store, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
            GRDBKeyValueStoreMigrator<Any>(label: "StickerManager.store", keyStore: StickerManager.store, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
            GRDBKeyValueStoreMigrator<Any>(label: "StickerManager.emojiMapStore", keyStore: StickerManager.emojiMapStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
            GRDBKeyValueStoreMigrator<Any>(label: "preferences", keyStore: environment.preferences.keyValueStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),

            GRDBKeyValueStoreMigrator<Any>(label: "OWSOrphanDataCleaner", keyStore: OWSOrphanDataCleaner.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
            GRDBKeyValueStoreMigrator<Any>(label: "contactsManager", keyStore: contactsManager.keyValueStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSDeviceManager", keyStore: OWSDeviceManager.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSReadReceiptManager", keyStore: OWSReadReceiptManager.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWS2FAManager", keyStore: OWS2FAManager.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSBlockingManager", keyStore: OWSBlockingManager.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "typingIndicators", keyStore: typingIndicators.keyValueStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "udManager.keyValueStore", keyStore: udManager.keyValueStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "udManager.phoneNumberAccessStore", keyStore: udManager.phoneNumberAccessStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "udManager.uuidAccessStore", keyStore: udManager.uuidAccessStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "CallKitIdStore.phoneNumber", keyStore: CallKitIdStore.phoneNumber(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "CallKitIdStore.uuid", keyStore: CallKitIdStore.uuidStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "signalService", keyStore: signalService.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSStorageServiceOperation", keyStore: StorageServiceOperation.keyValueStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),

            GRDBKeyValueStoreMigrator<Any>(label: "OWSDatabaseMigration", keyStore: OWSDatabaseMigration.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSProfileManager.whitelistedPhoneNumbersStore", keyStore: profileManager.whitelistedPhoneNumbersStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSProfileManager.whitelistedUUIDsStore", keyStore: profileManager.whitelistedUUIDsStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSProfileManager.whitelistedGroupsStore", keyStore: profileManager.whitelistedGroupsStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSSounds", keyStore: OWSSounds.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "Theme", keyStore: Theme.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSSyncManager", keyStore: OWSSyncManager.keyValueStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSOutgoingReceiptManager.deliveryReceiptStore", keyStore: OWSOutgoingReceiptManager.deliveryReceiptStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSOutgoingReceiptManager.readReceiptStore", keyStore: OWSOutgoingReceiptManager.readReceiptStore(), ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1)
        ]

        for (label, keyStore) in YDBToGRDBMigration.otherKeyStores {
            result.append(GRDBKeyValueStoreMigrator<Any>(label: label, keyStore: keyStore, ydbTransaction: ydbTransaction, memorySamplerRatio: 0.1))
        }

        return result
    }

    private func allUnorderedRecordMigrators(ydbTransaction: YapDatabaseReadTransaction) -> [GRDBMigrator] {
        // TODO: We need to test all of these migrations.
        return [
            GRDBUnorderedRecordMigrator<TSAttachment>(label: "attachments", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.003),
            GRDBUnorderedRecordMigrator<OWSMessageContentJob>(label: "contentJob", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.05),
            GRDBUnorderedRecordMigrator<OWSRecipientIdentity>(label: "recipientIdentities", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.02),
            GRDBUnorderedRecordMigrator<TSThread>(label: "threads", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<ExperienceUpgrade>(label: "ExperienceUpgrade", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<StickerPack>(label: "StickerPack", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<InstalledSticker>(label: "InstalledSticker", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<KnownStickerPack>(label: "KnownStickerPack", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<OWSBackupFragment>(label: "OWSBackupFragment", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<SignalRecipient>(label: "SignalRecipient", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<OWSDisappearingMessagesConfiguration>(label: "OWSDisappearingMessagesConfiguration", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<SignalAccount>(label: "SignalAccount", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<OWSLinkedDeviceReadReceipt>(label: "OWSLinkedDeviceReadReceipt", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<OWSDevice>(label: "OWSDevice", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2),
            GRDBUnorderedRecordMigrator<OWSUserProfile>(label: "OWSUserProfile", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.02),
            GRDBUnorderedRecordMigrator<TSRecipientReadReceipt>(label: "TSRecipientReadReceipt", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2)
        ]
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
    let ext: YapDatabaseAutoViewTransaction?

    init(transaction: YapDatabaseReadTransaction) {
        self.ext = transaction.safeAutoViewTransaction(extensionName)
    }

    func ext(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseAutoViewTransaction? {
        return transaction.safeAutoViewTransaction(extensionName)
    }

    public func enumerateInteractions(transaction: YapDatabaseReadTransaction, block: @escaping (TSInteraction) throws -> Void ) throws {
        try enumerateInteractions(transaction: ext(transaction), block: block)
    }

    public func enumerateInteractions(block: @escaping (TSInteraction) throws -> Void) throws {
        try enumerateInteractions(transaction: ext, block: block)
    }

    func enumerateInteractions(transaction: YapDatabaseAutoViewTransaction?, block: @escaping (TSInteraction) throws -> Void) throws {
        guard let transaction = transaction else {
            owsFailDebug("Missing transaction.")
            return
        }
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
    var ext: YapDatabaseSecondaryIndexTransaction?

    init(transaction: YapDatabaseReadTransaction) {
        self.ext = transaction.safeSecondaryIndexTransaction(extensionName)
    }

    public func enumerateJobRecords(block: @escaping (SSKJobRecord) throws -> Void) throws {
        try enumerateJobRecords(ext: ext, block: block)
    }

    func enumerateJobRecords(ext: YapDatabaseSecondaryIndexTransaction?, block: @escaping (SSKJobRecord) throws -> Void) throws {
        guard let ext = ext else {
            owsFailDebug("Missing ext.")
            return
        }

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

private class LegacyDecryptJobFinder {

    let ydbTransaction: YapDatabaseReadTransaction

    init(transaction: YapDatabaseReadTransaction) {
        ydbTransaction = transaction
    }

    func enumerateJobRecords(block: @escaping (OWSMessageDecryptJob) throws -> Void) throws {
        try autoreleasepool {
            var errorToRaise: Error?
            let legacyFinder = OWSMessageDecryptJobFinder()
            try legacyFinder.enumerateJobs(transaction: ydbTransaction.asAnyRead) { (job, stop) in
                do {
                    try block(job)
                } catch {
                    owsFailDebug("error: \(error)")
                    errorToRaise = error
                    stop.pointee = true
                }
            }

            if let errorToRaise = errorToRaise {
                throw errorToRaise
            }
        }
    }
}

// MARK: -

@objc
public protocol GRDBMigrator {
    func migrate(grdbTransaction: GRDBWriteTransaction) throws
}

// MARK: -

public class GRDBKeyValueStoreMigrator<T> : GRDBMigrator {
    private let label: String
    private let finder: LegacyKeyValueFinder<T>
    private let memorySamplerRatio: Float

    init(label: String, keyStore: SDSKeyValueStore, ydbTransaction: YapDatabaseReadTransaction, memorySamplerRatio: Float) {
        self.label = label
        self.finder = LegacyKeyValueFinder(store: keyStore, transaction: ydbTransaction)
        self.memorySamplerRatio = memorySamplerRatio
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate \(label)", memorySamplerRatio: memorySamplerRatio) { memorySampler in
            var recordCount = 0
            try finder.enumerateLegacyKeysAndObjects { legacyKey, legacyObject in
                recordCount += 1
                if let legacyData = legacyObject as? Data {
                    self.finder.store.setData(legacyData, key: legacyKey, transaction: grdbTransaction.asAnyWrite)
                } else {
                    self.finder.store.setObject(legacyObject, key: legacyKey, transaction: grdbTransaction.asAnyWrite)
                }
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }
}

// MARK: -

public class GRDBUnorderedRecordMigrator<T> : GRDBMigrator where T: SDSModel {
    private let label: String
    private let finder: LegacyUnorderedFinder<T>
    private let memorySamplerRatio: Float

    init(label: String, ydbTransaction: YapDatabaseReadTransaction, memorySamplerRatio: Float) {
        self.label = label
        self.finder = LegacyUnorderedFinder(transaction: ydbTransaction)
        self.memorySamplerRatio = memorySamplerRatio
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate \(label)", memorySamplerRatio: memorySamplerRatio) { memorySampler in
            var recordCount = 0
            try finder.enumerateLegacyObjects { legacyRecord in
                recordCount += 1
                legacyRecord.anyInsert(transaction: grdbTransaction.asAnyWrite)
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }
}

// MARK: -

public class GRDBJobRecordMigrator: GRDBMigrator {
    private let finder: LegacyJobRecordFinder

    init(ydbTransaction: YapDatabaseReadTransaction) {
        self.finder = LegacyJobRecordFinder(transaction: ydbTransaction)
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate SSKJobRecord", memorySamplerRatio: 0.02) { memorySampler in
            var recordCount = 0
            try finder.enumerateJobRecords { legacyRecord in
                recordCount += 1
                legacyRecord.anyInsert(transaction: grdbTransaction.asAnyWrite)
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }
}

// MARK: -

public class GRDBInteractionMigrator: GRDBMigrator {
    private let finder: LegacyInteractionFinder

    init(ydbTransaction: YapDatabaseReadTransaction) {
        self.finder = LegacyInteractionFinder(transaction: ydbTransaction)
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate Interactions", memorySamplerRatio: 0.001) { memorySampler in
            var recordCount = 0
            try finder.enumerateInteractions { legacyInteraction in
                legacyInteraction.anyInsert(transaction: grdbTransaction.asAnyWrite)
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

public class GRDBDecryptJobMigrator: GRDBMigrator {
    private let finder: LegacyDecryptJobFinder

    init(ydbTransaction: YapDatabaseReadTransaction) {
        self.finder = LegacyDecryptJobFinder(transaction: ydbTransaction)
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        try Bench(title: "Migrate decrypt jobs", memorySamplerRatio: 0.001) { memorySampler in
            var recordCount = 0
            try finder.enumerateJobRecords { legacyJob in
                let newJob = SSKMessageDecryptJobRecord(envelopeData: legacyJob.envelopeData, label: SSKMessageDecryptJobQueue.jobRecordLabel)
                newJob.anyInsert(transaction: grdbTransaction.asAnyWrite)
                recordCount += 1
                if (recordCount % 500 == 0) {
                    Logger.debug("saved \(recordCount) decrypt jobs")
                }
                memorySampler.sample()
            }
            Logger.info("completed with recordCount: \(recordCount)")
        }
    }
}
