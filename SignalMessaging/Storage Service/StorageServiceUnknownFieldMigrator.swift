//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/**
 * Utility class to simplify the transition when we start handling a previously-unknown storage
 * service field for the first time.
 *
 * ---
 * All this is rather complicated. Lets start with an example:
 *
 * Say we have some setting for dark mode (isDarkMode) on iOS and Desktop.
 * Desktop has been syncing the setting to storage service. iOS has not. We want to start syncing it.
 * Locally we have three states: UNSET, FALSE, TRUE.
 *
 * If we just naively added the field to our local proto definition, we'd recognize it the next time
 * we read from storage service, but our naive merging logic would overwrite our local state
 * with the state we see in storage service. Uh oh! We should respect local state!
 *
 * Ok so maybe we prefer local state for the primary, so we ignore the value when we read and
 * keep our local state instead. We do that, write our local state, Desktop reads it, and then the user
 * updates the value on Desktop. Next time we read from storage service on iOS...we drop the
 * value the user set on Desktop in favor of our local value! Uh oh!
 *
 * In short, what we need is to ignore the value on reads UNTIL we get a chance to write at least once,
 * and then we can start respecting the value on reads.
 * This class solves this problem generally.
 *
 * ---
 *
 * Now, how does this class actually work? The scaffolding handles all the hooks for you so
 * that you can write a "migration" that does some subset of three things:
 * 1. ``MergeUnknownFields`` - do any special one-time handling the _first_ time we learn about
 *   some previously-unknown proto field. This lets you e.g. do any one-time merging of remote state
 *   into local state. In the isDarkMode example, we would take this opportunity to overwrite a local
 *   UNSET value with any value in storage service.
 *
 * Next are two methods that run on every record we read/write until we get the chance to successfully
 * write to storage service once. This lets us intercept records _before_ the standard merging code runs
 * and perform modifications while we are in this "in between" state when we first handle unknown fields.
 * 2. ``InterceptRemoteManifest`` - Take a record from a storage service manifest we fetched
 *   remotely and are about to merge with local state, and modify it _before_ we merge.
 *   In the isDarkMode example, we would overwrite the remote state with local state, so that the merge
 *   code always sees the remote state and local state as the same and changes nothing.
 * 3. ``InterceptLocalManifest`` - Take a record from a storage service manifest we generated
 *   locally and are about to _write_ to a remote, and modify it _before_ we write it.
 *   In the isDarkMode example we would do nothing in this step, but if we had some more complex merging
 *   logic that reconciles local and remote state, you could imagine this coming in handy.
 *
 * So the general flow is:
 * 1. Have some unknown field (isDarkMode) in storage service
 * 2. Update to a build that knows about this field for the first time
 * 3. Once, the _very first_ time on launch of this new build: run ``MergeUnknownFields`` providing
 *   all records with unknown fields. (May be empty. See ##Unknown Field Default Values## below).
 * 4. If we read from storage service: pass every read record to ``InterceptRemoteManifest`` before
 *   merging locally. (We pretend isDarkMode remote state is the same as local state so we never overwrite local state yet).
 * 5. If we write to storage service: pass every generated record to ``InterceptLocalManifest`` before
 *   writing remotely.
 * 6. Repeat 4 and 5 for every read/write until some write succeeds (step 3 is never repeated!)
 * 7. Succesfully write to storage service
 * 8. Done! Migration marked complete.
 *
 * To see this in pseudocode for the isDarkMode example, see the ``MigrationId.noOpExample`` migration below.
 *
 * ---
 *
 * There are some gotchas with ``MergeUnknownFields``.
 *
 * ##Unknown Field Default Values##
 *
 * One quirk of unknown fields in protos: if a field uses a primitive type (e.g. bool) and
 * is set to its default value (e.g. false), the serialized representation of that proto simply
 * omits the field entirely.
 * When a client that is unaware of the field parses such a proto, it doesn't know to
 * look for the field and doesn't see anything in the serialized bytes, so it has no idea
 * there is an unknown field at all.
 *
 * This means our "records with unknown fields" actually means "records with unknown
 * fields set to non-default values". So your ``MergeUnknownFields`` implementation
 * **SHOULD NOT** assume it is getting every record that had an unknown field; it only
 * gets those with non-default values. (And might actually be an empty array if all records
 * use default values!)
 *
 * What this means in practice is you should NOT write for loops over the passed in records;
 * instead you should loop over objects in our database (e.g. TSGroupThreads) and match those
 * against any passed in records (e.g. by groupId) and, if not present, assume the default value.
 *
 * ##Triggering Storage Service Writes##
 *
 * Most of the time, if you're merging remote state in ``MergeUnknownFields``, you will want
 * to write back the results of the merge to storage service. The way to do this is to mark any updated
 * record as needing an update via normal mechanisms, e.g. for the local account record you would call
 * `storageServiceManager.recordPendingLocalAccountUpdates()`
 */
public class StorageServiceUnknownFieldMigrator {

    fileprivate enum MigrationId: UInt, CaseIterable {
        case noOpExample = 0

        // MARK: - Migration Insertion Point
        // Never, ever, ever insert another migration before an existing one.
        // Increase the value only.

        static var highestKnownValue: UInt {
            return allCases.lazy.map(\.rawValue).max() ?? 0
        }
    }

    fileprivate enum Actions<RecordType: MigrateableStorageServiceRecordType> {
        typealias MergeUnknownFields = (_ records: [RecordType], _ isPrimaryDevice: Bool, _ tx: SDSAnyWriteTransaction) -> Void
        typealias InterceptRemoteManifest = (RecordType, inout RecordType.Builder, _ isPrimaryDevice: Bool, _ tx: SDSAnyReadTransaction) -> Void
        typealias InterceptLocalManifest = (RecordType, inout RecordType.Builder, _ isPrimaryDevice: Bool, _ tx: SDSAnyReadTransaction) -> Void
    }

    private static func registerMigrations(migrator: Migrator) {
        // This is simply an example migration (commented out) for how you _would_ migrate
        // if you had an isDarkMode setting that already existed both locally and in storage service
        // that needed to be merged such that the local value, if set, "wins" on the primary.
        // See doc comment on this class for context.
        migrator.registerMigration(
            .noOpExample,
            record: StorageServiceProtoAccountRecord.self,
            mergeUnknownFields: { accountRecords, isPrimaryDevice, tx in
                /**
                let isRemoteDarkMode = accountRecords.first?.isDarkMode ?? false
                guard isPrimaryDevice else {
                    // Just take what we have in storage service.
                    localDarkModeSetting.set(isRemoteDarkMode, tx: tx)
                }
                switch (localDarkModeSetting.get(tx: tx)) {
                case .TRUE, .FALSE:
                    // Ignore if set locally, schedule an update so we overwrite
                    // storage service with our local value.
                    NSObject.storageServiceManager.recordPendingLocalAccountUpdates()
                case .UNSET:
                    // Just take what we have in storage service.
                    localDarkModeSetting.set(isRemoteDarkMode, tx: tx)
                }
                */
            },
            interceptRemoteManifest: { accountRecord, accountRecordBuilder, isPrimaryDevice, tx in
                /**
                if isPrimaryDevice {
                    // Until we get the chance to write to storage service, we want to
                    // always use our local value. Overwrite the value to our local value
                    // so that the merge logic uses it.
                    accountRecordBuilder.setIsDarkMode(localDarkModeSetting.get(tx: tx))
                }
                */
                return
            },
            interceptLocalManifest: { accountRecord, accountRecordBuilder, isPrimaryDevice, tx in
                /**
                // Nothing to intercept for writes in this case
                 */
                return
            }
        )

        // MARK: - Migration Insertion Point
    }

    // MARK: - Public methods

    // If you are just writing a new migration, you don't need to worry about these.

    /// Check this before merging records with unknown fields; if true, call ``runMigrationsForRecordsWithUnknownFields``
    public static func needsAnyUnknownFieldsMigrations(tx: SDSAnyReadTransaction) -> Bool {
        return necessaryMigrations(forKey: Keys.lastRunUnknownFieldsMerge, tx: tx).isEmpty.negated
    }

    /// Check this before merging records from a remote manifest; if true, call ``interceptRemoteManifestBeforeMerging``
    public static func shouldInterceptRemoteManifestBeforeMerging(tx: SDSAnyReadTransaction) -> Bool {
        return necessaryMigrations(forKey: Keys.lastSuccessfulStorageServiceWrite, tx: tx).isEmpty.negated
    }

    /// Check this before uploading records generated locally; if true, call ``interceptLocalManifestBeforeUploading``
    public static func shouldInterceptLocalManifestBeforeUploading(tx: SDSAnyReadTransaction) -> Bool {
        return necessaryMigrations(forKey: Keys.lastSuccessfulStorageServiceWrite, tx: tx).isEmpty.negated
    }

    /// Call this after every succesful write of a manifest to Storage Service.
    public static func didWriteToStorageService(tx: SDSAnyWriteTransaction) {
        kvStore.setUInt(MigrationId.highestKnownValue, key: Keys.lastSuccessfulStorageServiceWrite, transaction: tx)
    }

    /// Given an array of every record from the latest synced manifest known to have unknown fields, runs any necessary migrations.
    public static func runMigrationsForRecordsWithUnknownFields(
        records: [any MigrateableStorageServiceRecordType],
        tx: SDSAnyWriteTransaction
    ) {
        return _runMigrationsForRecordsWithUnknownFields(records: records, tx: tx)
    }

    public static func interceptRemoteManifestBeforeMerging<RecordType>(
        record: RecordType,
        tx: SDSAnyReadTransaction
    ) -> RecordType {
        guard let recordTypecast = record as? (any MigrateableStorageServiceRecordType) else {
            // Not migrateable. Just no-op.
            return record
        }
        return _interceptRemoteManifestBeforeMerging(record: recordTypecast, tx: tx) as! RecordType
    }

    public static func interceptLocalManifestBeforeUploading<RecordType>(
        record: RecordType,
        tx: SDSAnyReadTransaction
    ) -> RecordType {
        guard let recordTypecast = record as? (any MigrateableStorageServiceRecordType) else {
            // Not migrateable. Just no-op.
            return record
        }
        return _interceptLocalManifestBeforeUploading(record: recordTypecast, tx: tx) as! RecordType
    }

    // MARK: - Private Implementation

    private enum Keys {
        // The value at this key is a UInt representing the highest known MigrationId
        // at the time this device last merged unknown fields from a previously-stored
        // storage service manifest. If this number is lower than the current highest known
        // MigrationId, we should run any unknown field merging operation migrations higher
        // than the stored value.
        static let lastRunUnknownFieldsMerge = "lastRunUnknownFieldsMerge"

        // The value at this key is a UInt representing the highest known MigrationId
        // at the time that this device last succesfully updated the manifest in storage service.
        // If this number is lower than the current highest known MigrationId, we should run any
        // higher value migrations' Record mutation operations on every record we read and write
        // locally.
        static let lastSuccessfulStorageServiceWrite = "lastSuccessfulStorageServiceWrite"
    }
    private static var kvStore = SDSKeyValueStore(collection: "StorageServiceUnknownFieldMigrator")

    private class Migrator {
        var migrations: [MigrationId: any StorageServiceUnknownFieldMigration] = [:]

        func registerMigration<RecordType: MigrateableStorageServiceRecordType>(
            _ migrationId: MigrationId,
            record: RecordType.Type,
            mergeUnknownFields: @escaping Actions<RecordType>.MergeUnknownFields,
            interceptRemoteManifest: @escaping Actions<RecordType>.InterceptRemoteManifest,
            interceptLocalManifest: @escaping Actions<RecordType>.InterceptLocalManifest
        ) {
            let migration = StorageServiceUnknownFieldMigrationImpl(
                id: migrationId,
                mergeUnknownFields: mergeUnknownFields,
                interceptRemoteManifest: interceptRemoteManifest,
                interceptLocalManifest: interceptLocalManifest
            )
            migrations[migrationId] = migration
        }
    }

    private static var _migrator: Migrator?

    private static var migrator: Migrator {
        if let _migrator {
            return _migrator
        }
        let migrator = Migrator()
        registerMigrations(migrator: migrator)
        _migrator = migrator
        return migrator
    }

    private static func necessaryMigrations(
        forKey key: String,
        tx: SDSAnyReadTransaction
    ) -> LazyFilterSequence<[MigrationId]> {
        guard let latestMigrationId = kvStore.getUInt(key, transaction: tx) else {
            // We've never run any migrations!
            return MigrationId.allCases.lazy.filter { _ in true }
        }
        return MigrationId.allCases.lazy.filter { $0.rawValue > latestMigrationId }
    }

    private static func _runMigrationsForRecordsWithUnknownFields(
        records: [any MigrateableStorageServiceRecordType],
        tx: SDSAnyWriteTransaction
    ) {
        let necessaryMigrations = Self.necessaryMigrations(forKey: Keys.lastRunUnknownFieldsMerge, tx: tx)
        if necessaryMigrations.isEmpty {
            return
        }

        guard let isPrimaryDevice = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read).isPrimaryDevice else {
            // Not registered!
            return
        }

        func doMergeUnknownFields<Migration: StorageServiceUnknownFieldMigration>(
            records: [any MigrateableStorageServiceRecordType],
            migration: Migration
        ) {
            let filteredRecords = records.compactMap { $0 as? Migration.RecordType }
            migration.mergeUnknownFields(filteredRecords, isPrimaryDevice, tx)
        }

        necessaryMigrations.forEach { migrationId in
            guard let migration = migrator.migrations[migrationId] else {
                return
            }
            doMergeUnknownFields(records: records, migration: migration)
        }

        kvStore.setUInt(MigrationId.highestKnownValue, key: Keys.lastRunUnknownFieldsMerge, transaction: tx)
    }

    private static func _interceptRemoteManifestBeforeMerging<RecordType: MigrateableStorageServiceRecordType>(
        record: RecordType,
        tx: SDSAnyReadTransaction
    ) -> RecordType {
        let necessaryMigrations = Self.necessaryMigrations(forKey: Keys.lastSuccessfulStorageServiceWrite, tx: tx)
        if necessaryMigrations.isEmpty {
            return record
        }

        guard let isPrimaryDevice = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read).isPrimaryDevice else {
            // Not registered!
            return record
        }

        var _builder: RecordType.Builder?

        func doModifyRemoteManifest<Migration: StorageServiceUnknownFieldMigration>(
            migration: Migration
        ) {
            guard RecordType.self == Migration.RecordType.self else {
                return
            }
            var builder = _builder ?? record.asBuilder()
            var typecastBuilder = builder as! Migration.RecordType.Builder
            migration.interceptRemoteManifest(record as! Migration.RecordType, &typecastBuilder, isPrimaryDevice, tx)
            _builder = (typecastBuilder as! RecordType.Builder)
        }

        necessaryMigrations.forEach { migrationId in
            guard let migration = migrator.migrations[migrationId] else {
                return
            }
            doModifyRemoteManifest(migration: migration)
        }

        if let builder = _builder {
            return builder.buildInfallibly()
        } else {
            // It was unmodified.
            return record
        }
    }

    private static func _interceptLocalManifestBeforeUploading<RecordType: MigrateableStorageServiceRecordType>(
        record: RecordType,
        tx: SDSAnyReadTransaction
    ) -> RecordType {
        let necessaryMigrations = Self.necessaryMigrations(forKey: Keys.lastSuccessfulStorageServiceWrite, tx: tx)
        if necessaryMigrations.isEmpty {
            return record
        }

        guard let isPrimaryDevice = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read).isPrimaryDevice else {
            // Not registered!
            return record
        }

        var _builder: RecordType.Builder?

        func doModifyLocalManifest<Migration: StorageServiceUnknownFieldMigration>(
            migration: Migration
        ) {
            guard RecordType.self == Migration.RecordType.self else {
                return
            }
            var builder = _builder ?? record.asBuilder()
            var typecastBuilder = builder as! Migration.RecordType.Builder
            migration.interceptLocalManifest(record as! Migration.RecordType, &typecastBuilder, isPrimaryDevice, tx)
            _builder = (typecastBuilder as! RecordType.Builder)
        }

        necessaryMigrations.forEach { migrationId in
            guard let migration = migrator.migrations[migrationId] else {
                return
            }
            doModifyLocalManifest(migration: migration)
        }

        if let builder = _builder {
            return builder.buildInfallibly()
        } else {
            // It was unmodified.
            return record
        }
    }
}

public protocol MigrateableStorageServiceRecordType {
    associatedtype Builder: MigrateableStorageServiceRecordTypeBuilder where Builder.RecordType == Self

    func asBuilder() -> Builder
}

public protocol MigrateableStorageServiceRecordTypeBuilder {
    associatedtype RecordType: MigrateableStorageServiceRecordType

    func buildInfallibly() -> RecordType
}

private protocol StorageServiceUnknownFieldMigration {

    associatedtype RecordType: MigrateableStorageServiceRecordType

    var mergeUnknownFields: StorageServiceUnknownFieldMigrator.Actions<RecordType>.MergeUnknownFields { get }
    var interceptRemoteManifest: StorageServiceUnknownFieldMigrator.Actions<RecordType>.InterceptRemoteManifest { get }
    var interceptLocalManifest: StorageServiceUnknownFieldMigrator.Actions<RecordType>.InterceptLocalManifest { get }
}

extension StorageServiceUnknownFieldMigrator {

    private struct StorageServiceUnknownFieldMigrationImpl<RecordType: MigrateableStorageServiceRecordType>: StorageServiceUnknownFieldMigration {
        let id: StorageServiceUnknownFieldMigrator.MigrationId
        let mergeUnknownFields: Actions<RecordType>.MergeUnknownFields
        let interceptRemoteManifest: Actions<RecordType>.InterceptRemoteManifest
        let interceptLocalManifest: Actions<RecordType>.InterceptLocalManifest
    }
}

extension StorageServiceProtoAccountRecord: MigrateableStorageServiceRecordType {}
extension StorageServiceProtoContactRecord: MigrateableStorageServiceRecordType {}
extension StorageServiceProtoGroupV1Record: MigrateableStorageServiceRecordType {}
extension StorageServiceProtoGroupV2Record: MigrateableStorageServiceRecordType {}

extension StorageServiceProtoAccountRecordBuilder: MigrateableStorageServiceRecordTypeBuilder {}
extension StorageServiceProtoContactRecordBuilder: MigrateableStorageServiceRecordTypeBuilder {}
extension StorageServiceProtoGroupV1RecordBuilder: MigrateableStorageServiceRecordTypeBuilder {}
extension StorageServiceProtoGroupV2RecordBuilder: MigrateableStorageServiceRecordTypeBuilder {}
