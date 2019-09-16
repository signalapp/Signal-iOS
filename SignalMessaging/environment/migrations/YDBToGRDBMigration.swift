//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
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

        let startDate = Date()

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

        removeYdb()

        let migrationDuration = abs(startDate.timeIntervalSinceNow)
        Logger.info("Migration duration: \(OWSFormat.formatDurationSeconds(Int(migrationDuration))) (\(migrationDuration))")
    }

    func removeYdb() {
        guard !FeatureFlags.preserveYdb else {
            return
        }
        guard FeatureFlags.storageMode != .grdbThrowawayIfMigrating else {
            return
        }

        guard let primaryStorage = primaryStorage else {
            owsFail("Missing primaryStorage.")
        }
        let ydbReadConnection = primaryStorage.newDatabaseConnection()
        ydbReadConnection.readWrite { ydbTransaction in
            // Note: we deliberately _DO NOT_ deserialize the
            // models as we delete them from YDB. That would
            // have undesired side effects, e.g. deleting
            // attachments on disk.
            ydbTransaction.removeAllObjectsInAllCollections()
        }

        OWSStorage.deleteDatabaseFiles()
        OWSStorage.deleteDBKeys()
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
            GRDBKeyValueStoreMigrator<PreKeyRecord>(label: "preKey Store", keyStore: preKeyStore.keyStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "preKey Metadata", keyStore: preKeyStore.metadataStore, ydbTransaction: ydbTransaction),

            GRDBKeyValueStoreMigrator<SignedPreKeyRecord>(label: "signedPreKey Store", keyStore: signedPreKeyStore.keyStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "signedPreKey Metadata", keyStore: signedPreKeyStore.metadataStore, ydbTransaction: ydbTransaction),

            GRDBKeyValueStoreMigrator<ECKeyPair>(label: "ownIdentity", keyStore: identityManager.ownIdentityKeyValueStore, ydbTransaction: ydbTransaction),

            GRDBKeyValueStoreMigrator<[Int: SessionRecord]>(label: "sessionStore", keyStore: sessionStore.keyValueStore, ydbTransaction: ydbTransaction),

            GRDBKeyValueStoreMigrator<String>(label: "queuedVerificationStateSyncMessages", keyStore: identityManager.queuedVerificationStateSyncMessagesKeyValueStore, ydbTransaction: ydbTransaction),

            GRDBKeyValueStoreMigrator<Any>(label: "tsAccountManager", keyStore: tsAccountManager.keyValueStore, ydbTransaction: ydbTransaction),

            GRDBKeyValueStoreMigrator<Any>(label: "AppPreferences", keyStore: AppPreferences.store, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "SSKPreferences", keyStore: SSKPreferences.store, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "StickerManager.store", keyStore: StickerManager.store, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "StickerManager.emojiMapStore", keyStore: StickerManager.emojiMapStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "preferences", keyStore: environment.preferences.keyValueStore, ydbTransaction: ydbTransaction),

            GRDBKeyValueStoreMigrator<Any>(label: "OWSOrphanDataCleaner", keyStore: OWSOrphanDataCleaner.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "contactsManager", keyStore: contactsManager.keyValueStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSDeviceManager", keyStore: OWSDeviceManager.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSReadReceiptManager", keyStore: OWSReadReceiptManager.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWS2FAManager", keyStore: OWS2FAManager.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSBlockingManager", keyStore: OWSBlockingManager.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "typingIndicators", keyStore: typingIndicators.keyValueStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "udManager.keyValueStore", keyStore: udManager.keyValueStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "udManager.phoneNumberAccessStore", keyStore: udManager.phoneNumberAccessStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "udManager.uuidAccessStore", keyStore: udManager.uuidAccessStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "CallKitIdStore.phoneNumber", keyStore: CallKitIdStore.phoneNumber(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "CallKitIdStore.uuid", keyStore: CallKitIdStore.uuidStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "signalService", keyStore: signalService.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSStorageServiceOperation", keyStore: StorageServiceOperation.keyValueStore, ydbTransaction: ydbTransaction),

            GRDBKeyValueStoreMigrator<Any>(label: "OWSDatabaseMigration", keyStore: OWSDatabaseMigration.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSProfileManager.whitelistedPhoneNumbersStore", keyStore: profileManager.whitelistedPhoneNumbersStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSProfileManager.whitelistedUUIDsStore", keyStore: profileManager.whitelistedUUIDsStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSProfileManager.whitelistedGroupsStore", keyStore: profileManager.whitelistedGroupsStore, ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSSounds", keyStore: OWSSounds.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "Theme", keyStore: Theme.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSSyncManager", keyStore: OWSSyncManager.keyValueStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSOutgoingReceiptManager.deliveryReceiptStore", keyStore: OWSOutgoingReceiptManager.deliveryReceiptStore(), ydbTransaction: ydbTransaction),
            GRDBKeyValueStoreMigrator<Any>(label: "OWSOutgoingReceiptManager.readReceiptStore", keyStore: OWSOutgoingReceiptManager.readReceiptStore(), ydbTransaction: ydbTransaction)
        ]

        for (label, keyStore) in YDBToGRDBMigration.otherKeyStores {
            result.append(GRDBKeyValueStoreMigrator<Any>(label: label, keyStore: keyStore, ydbTransaction: ydbTransaction))
        }

        return result
    }

    private func allUnorderedRecordMigrators(ydbTransaction: YapDatabaseReadTransaction) -> [GRDBMigrator] {
        // TODO: We need to test all of these migrations.
        return [
            GRDBUnorderedRecordMigrator<TSAttachment>(label: "TSAttachment", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<OWSMessageContentJob>(label: "OWSMessageContentJob", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<OWSRecipientIdentity>(label: "OWSRecipientIdentity", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<TSThread>(label: "TSThread", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<ExperienceUpgrade>(label: "ExperienceUpgrade", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<StickerPack>(label: "StickerPack", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<InstalledSticker>(label: "InstalledSticker", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<KnownStickerPack>(label: "KnownStickerPack", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<OWSBackupFragment>(label: "OWSBackupFragment", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<SignalRecipient>(label: "SignalRecipient", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<OWSDisappearingMessagesConfiguration>(label: "OWSDisappearingMessagesConfiguration", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<SignalAccount>(label: "SignalAccount", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<OWSLinkedDeviceReadReceipt>(label: "OWSLinkedDeviceReadReceipt", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<OWSDevice>(label: "OWSDevice", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<OWSUserProfile>(label: "OWSUserProfile", ydbTransaction: ydbTransaction),
            GRDBUnorderedRecordMigrator<TSRecipientReadReceipt>(label: "TSRecipientReadReceipt", ydbTransaction: ydbTransaction)
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

    public var count: UInt {
        return transaction.numberOfKeys(inCollection: collection)
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

    public var count: UInt {
        guard let ext = ext else {
            owsFailDebug("Missing view transcation.")
            return 0
        }
        var count: UInt = 0
        ext.getNumberOfRows(&count, matching: query)
        return count
    }

    private var query: YapDatabaseQuery {
        let queryFormat = String(format: "ORDER BY %@", "sortId")
        return YapDatabaseQuery(string: queryFormat, parameters: [])
    }

    public func enumerateJobRecords(block: @escaping (SSKJobRecord) throws -> Void) throws {
        try enumerateJobRecords(ext: ext, block: block)
    }

    func enumerateJobRecords(ext: YapDatabaseSecondaryIndexTransaction?, block: @escaping (SSKJobRecord) throws -> Void) throws {
        guard let ext = ext else {
            owsFailDebug("Missing ext.")
            return
        }

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

    var count: UInt {

        let legacyFinder = OWSMessageDecryptJobFinder()
        return legacyFinder.queuedJobCount(with: ydbTransaction.asAnyRead)
    }

    func enumerateJobRecords(block: @escaping (OWSMessageDecryptJob) throws -> Void) throws {
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

// MARK: -

@objc
public protocol GRDBMigrator {
    var label: String { get }

    var count: UInt { get }

    func migrate(grdbTransaction: GRDBWriteTransaction) throws
}

extension GRDBMigrator {
    func memorySamplerRatio(count: UInt) -> Float {
        // Sample no more than N times for a given migration.
        let maxSampleCount: Float = 100

        let count = Float(self.count)
        guard count > maxSampleCount else {
                return 1
        }
        return maxSampleCount / count
    }
}

// MARK: -

public class GRDBKeyValueStoreMigrator<T>: GRDBMigrator {
    public let label: String
    private let keyStore: SDSKeyValueStore
    private let finder: LegacyKeyValueFinder<T>

    init(label: String, keyStore: SDSKeyValueStore, ydbTransaction: YapDatabaseReadTransaction) {
        self.label = "Migrate \(label)"
        self.keyStore = keyStore
        self.finder = LegacyKeyValueFinder(store: keyStore, transaction: ydbTransaction)
    }

    public var count: UInt {
        return finder.count
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        let count = self.count
        Logger.info("\(label): \(count)")
        try Bench(title: label, memorySamplerRatio: memorySamplerRatio(count: count)) { memorySampler in
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
            Logger.info("Completed with recordCount: \(recordCount)")
        }
    }
}

// MARK: -

public class GRDBUnorderedRecordMigrator<T>: GRDBMigrator where T: SDSModel {
    public let label: String
    private let finder: LegacyUnorderedFinder<T>

    init(label: String, ydbTransaction: YapDatabaseReadTransaction) {
        self.label = "Migrate \(label)"
        self.finder = LegacyUnorderedFinder(transaction: ydbTransaction)
    }

    public var count: UInt {
        return finder.count
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        let count = self.count
        Logger.info("\(label): \(count)")
        try Bench(title: label, memorySamplerRatio: memorySamplerRatio(count: count)) { memorySampler in
            var recordCount = 0
            try finder.enumerateLegacyObjects { legacyRecord in
                recordCount += 1
                legacyRecord.anyInsert(transaction: grdbTransaction.asAnyWrite)
                memorySampler.sample()
            }
            Logger.info("Completed with recordCount: \(recordCount)")
        }
    }
}

// MARK: -

public class GRDBJobRecordMigrator: GRDBMigrator {
    public let label: String
    private let finder: LegacyJobRecordFinder

    init(ydbTransaction: YapDatabaseReadTransaction) {
        self.label = "Migrate SSKJobRecord"
        self.finder = LegacyJobRecordFinder(transaction: ydbTransaction)
    }

    public var count: UInt {
        return finder.count
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        let count = self.count
        Logger.info("\(label): \(count)")
        try Bench(title: label, memorySamplerRatio: memorySamplerRatio(count: count)) { memorySampler in
            var recordCount = 0
            try finder.enumerateJobRecords { legacyRecord in
                recordCount += 1
                legacyRecord.anyInsert(transaction: grdbTransaction.asAnyWrite)
                memorySampler.sample()
            }
            Logger.info("Completed with recordCount: \(recordCount)")
        }
    }
}

// MARK: -

public class GRDBInteractionMigrator: GRDBMigrator {
    public let label: String
    private let finder: LegacyUnorderedFinder<TSInteraction>

    init(ydbTransaction: YapDatabaseReadTransaction) {
        self.label = "Migrate Interactions"
        self.finder = LegacyUnorderedFinder(transaction: ydbTransaction)
    }

    public var count: UInt {
        return finder.count
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        let count = self.count
        Logger.info("\(label): \(count)")
        try Bench(title: label, memorySamplerRatio: memorySamplerRatio(count: count)) { memorySampler in
            var recordCount = 0
            try finder.enumerateLegacyObjects { legacyInteraction in
                legacyInteraction.anyInsert(transaction: grdbTransaction.asAnyWrite)
                recordCount += 1
                if (recordCount % 500 == 0) {
                    Logger.debug("saved \(recordCount) interactions")
                }
                memorySampler.sample()
            }
            Logger.info("Completed with recordCount: \(recordCount)")
        }
    }
}

// MARK: -

public class GRDBDecryptJobMigrator: GRDBMigrator {
    public let label: String
    private let finder: LegacyDecryptJobFinder

    init(ydbTransaction: YapDatabaseReadTransaction) {
        self.label = "Migrate Interactions"
        self.finder = LegacyDecryptJobFinder(transaction: ydbTransaction)
    }

    public var count: UInt {
        return finder.count
    }

    public func migrate(grdbTransaction: GRDBWriteTransaction) throws {
        let count = self.count
        Logger.info("\(label): \(count)")
        try Bench(title: label, memorySamplerRatio: memorySamplerRatio(count: count)) { memorySampler in
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
            Logger.info("Completed with recordCount: \(recordCount)")
        }
    }
}
