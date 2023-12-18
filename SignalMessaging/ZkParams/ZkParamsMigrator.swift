//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class ZkParamsMigrator {
    private let db: DB
    private let groupsV2: GroupsV2Swift
    private let migrationStore: KeyValueStore
    private let tsAccountManager: TSAccountManager
    private let versionedProfiles: VersionedProfilesSwift

    init(
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        groupsV2: GroupsV2Swift,
        tsAccountManager: TSAccountManager,
        versionedProfiles: VersionedProfilesSwift
    ) {
        self.db = db
        self.groupsV2 = groupsV2
        // This collection name is weird for historical reasons.
        self.migrationStore = keyValueStoreFactory.keyValueStore(collection: "GroupsV2Impl.serviceStore")
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
        case 0, 1, 2, 3:
            // If you have anything other than v4, reset everything.
            fallthrough
        case 4 where !didStoreFinalV4ServerPublicParams(tx: tx):
            // If you have v4 and any params other than the ones just prior to the new
            // migration logic, reset everything.
            Logger.info("Resetting zkgroup-related state.")
            groupsV2.clearTemporalCredentials(tx: tx)
            versionedProfiles.clearProfileKeyCredentials(tx: tx)
            AppReadiness.runNowOrWhenAppDidBecomeReadyAsync { [groupsV2, tsAccountManager] in
                if tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
                    Logger.info("Re-uploading local profile due to zkgroup update.")
                    firstly {
                        groupsV2.reuploadLocalProfilePromise()
                    }.catch { error in
                        Logger.warn("Error: \(error)")
                    }
                }
            }
            fallthrough
        case 4:
            // If you have v4 and the right params, do a "normal" migration to v5. The
            // "normal" migration removes a key that we no longer need to track.
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

    private func didStoreFinalV4ServerPublicParams(tx: DBReadTransaction) -> Bool {
        return migrationStore.getString(Constants.lastServerPublicParamsKey, transaction: tx) == finalV4ServerPublicParams
    }

    private var finalV4ServerPublicParams: String {
        if TSConstants.isUsingProductionService {
            return "AMhf5ywVwITZMsff/eCyudZx9JDmkkkbV6PInzG4p8x3VqVJSFiMvnvlEKWuRob/1eaIetR31IYeAbm0NdOuHH8Qi+Rexi1wLlpzIo1gstHWBfZzy1+qHRV5A4TqPp15YzBPm0WSggW6PbSn+F4lf57VCnHF7p8SvzAA2ZZJPYJURt8X7bbg+H3i+PEjH9DXItNEqs2sNcug37xZQDLm7X36nOoGPs54XsEGzPdEV+itQNGUFEjY6X9Uv+Acuks7NpyGvCoKxGwgKgE5XyJ+nNKlyHHOLb6N1NuHyBrZrgtY/JYJHRooo5CEqYKBqdFnmbTVGEkCvJKxLnjwKWf+fEPoWeQFj5ObDjcKMZf2Jm2Ae69x+ikU5gBXsRmoF94GXTLfN0/vLt98KDPnxwAQL9j5V1jGOY8jQl6MLxEs56cwXN0dqCnImzVH3TZT1cJ8SW1BRX6qIVxEzjsSGx3yxF3suAilPMqGRp4ffyopjMD1JXiKR2RwLKzizUe5e8XyGOy9fplzhw3jVzTRyUZTRSZKkMLWcQ/gv0E4aONNqs4P"
        } else {
            return "ABSY21VckQcbSXVNCGRYJcfWHiAMZmpTtTELcDmxgdFbtp/bWsSxZdMKzfCp8rvIs8ocCU3B37fT3r4Mi5qAemeGeR2X+/YmOGR5ofui7tD5mDQfstAI9i+4WpMtIe8KC3wU5w3Inq3uNWVmoGtpKndsNfwJrCg0Hd9zmObhypUnSkfYn2ooMOOnBpfdanRtrvetZUayDMSC5iSRcXKpdlukrpzzsCIvEwjwQlJYVPOQPj4V0F4UXXBdHSLK05uoPBCQG8G9rYIGedYsClJXnbrgGYG3eMTG5hnx4X4ntARBgELuMWWUEEfSK0mjXg+/2lPmWcTZWR9nkqgQQP0tbzuiPm74H2wMO4u1Wafe+UwyIlIT9L7KLS19Aw8r4sPrXZSSsOZ6s7M1+rTJN0bI5CKY2PX29y5Ok3jSWufIKcgKOnWoP67d5b2du2ZVJjpjfibNIHbT/cegy/sBLoFwtHogVYUewANUAXIaMPyCLRArsKhfJ5wBtTminG/PAvuBdJ70Z/bXVPf8TVsR292zQ65xwvWTejROW6AZX6aqucUj"
        }
    }
}
