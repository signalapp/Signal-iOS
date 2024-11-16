//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class ZkParamsMigrator {
    private let appReadiness: AppReadiness
    private let authCredentialStore: AuthCredentialStore
    private let db: any DB
    private let migrationStore: KeyValueStore
    private let profileManager: ProfileManager
    private let tsAccountManager: TSAccountManager
    private let versionedProfiles: VersionedProfilesSwift

    init(
        appReadiness: AppReadiness,
        authCredentialStore: AuthCredentialStore,
        db: any DB,
        profileManager: ProfileManager,
        tsAccountManager: TSAccountManager,
        versionedProfiles: VersionedProfilesSwift
    ) {
        self.appReadiness = appReadiness
        self.authCredentialStore = authCredentialStore
        self.db = db
        // This collection name is weird for historical reasons.
        self.migrationStore = KeyValueStore(collection: "GroupsV2Impl.serviceStore")
        self.profileManager = profileManager
        self.tsAccountManager = tsAccountManager
        self.versionedProfiles = versionedProfiles
    }

    enum Constants {
        static let lastServerPublicParamsKey = "lastServerPublicParamsKey"
        static let lastZkGroupVersionCounterKey = "lastZKgroupVersionCounterKey"

        // This _does not_ conform to the public version number of the zkgroup
        // library. Instead it's a counter we should bump when we need to migrate
        // local data because of a ZkGroup update.
        static let zkGroupMigrationCounter: Int = 5
    }

    func migrateIfNeeded() {
        let oldMigrationCounter = db.read { tx -> Int in
            migrationStore.getInt(Constants.lastZkGroupVersionCounterKey, defaultValue: 0, transaction: tx)
        }

        guard oldMigrationCounter < Constants.zkGroupMigrationCounter else {
            // Either nothing has changed or nothing needs to be migrated.
            return
        }

        db.write { tx in
            performMigration(oldMigrationCounter: oldMigrationCounter, tx: tx)
            migrationStore.setInt(Constants.zkGroupMigrationCounter, key: Constants.lastZkGroupVersionCounterKey, transaction: tx)
        }
    }

    private func performMigration(oldMigrationCounter: Int, tx: DBWriteTransaction) {
        switch oldMigrationCounter {
        case 0, 1, 2, 3, 4:
            Logger.info("Resetting zkgroup-related state.")
            authCredentialStore.removeAllGroupAuthCredentials(tx: tx)
            versionedProfiles.clearProfileKeyCredentials(tx: tx)
            reuploadLocalProfile()
            migrationStore.removeValue(forKey: Constants.lastServerPublicParamsKey, transaction: tx)
            fallthrough
        case 5:
            // <Insert the v5 -> v6 migration logic here.> It might be a no-op. It
            // might clear some credentials. It might be something else entirely.
            fallthrough
        default:
            break
        }
    }

    // MARK: - Helpers

    private func reuploadLocalProfile() {
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { [db, profileManager, tsAccountManager] in
            guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                return
            }
            Logger.info("Re-uploading local profile due to zkgroup update.")
            firstly {
                db.write { tx in
                    profileManager.reuploadLocalProfile(
                        unsavedRotatedProfileKey: nil,
                        mustReuploadAvatar: false,
                        authedAccount: .implicit(),
                        tx: tx
                    )
                }
            }.catch { error in
                Logger.warn("Error: \(error)")
            }
        }
    }
}
