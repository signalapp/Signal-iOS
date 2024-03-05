//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalMessaging
@testable import SignalServiceKit

class ZkParamsMigratorTest: XCTestCase {
    private enum Constants {
        static let serverPublicParams2022_01_03 = "AMhf5ywVwITZMsff/eCyudZx9JDmkkkbV6PInzG4p8x3VqVJSFiMvnvlEKWuRob/1eaIetR31IYeAbm0NdOuHH8Qi+Rexi1wLlpzIo1gstHWBfZzy1+qHRV5A4TqPp15YzBPm0WSggW6PbSn+F4lf57VCnHF7p8SvzAA2ZZJPYJURt8X7bbg+H3i+PEjH9DXItNEqs2sNcug37xZQDLm7X36nOoGPs54XsEGzPdEV+itQNGUFEjY6X9Uv+Acuks7NpyGvCoKxGwgKgE5XyJ+nNKlyHHOLb6N1NuHyBrZrgtY/JYJHRooo5CEqYKBqdFnmbTVGEkCvJKxLnjwKWf+fEPoWeQFj5ObDjcKMZf2Jm2Ae69x+ikU5gBXsRmoF94GXQ=="
        static let serverPublicParams2022_08_08 = "AMhf5ywVwITZMsff/eCyudZx9JDmkkkbV6PInzG4p8x3VqVJSFiMvnvlEKWuRob/1eaIetR31IYeAbm0NdOuHH8Qi+Rexi1wLlpzIo1gstHWBfZzy1+qHRV5A4TqPp15YzBPm0WSggW6PbSn+F4lf57VCnHF7p8SvzAA2ZZJPYJURt8X7bbg+H3i+PEjH9DXItNEqs2sNcug37xZQDLm7X36nOoGPs54XsEGzPdEV+itQNGUFEjY6X9Uv+Acuks7NpyGvCoKxGwgKgE5XyJ+nNKlyHHOLb6N1NuHyBrZrgtY/JYJHRooo5CEqYKBqdFnmbTVGEkCvJKxLnjwKWf+fEPoWeQFj5ObDjcKMZf2Jm2Ae69x+ikU5gBXsRmoF94GXTLfN0/vLt98KDPnxwAQL9j5V1jGOY8jQl6MLxEs56cwXN0dqCnImzVH3TZT1cJ8SW1BRX6qIVxEzjsSGx3yxF3suAilPMqGRp4ffyopjMD1JXiKR2RwLKzizUe5e8XyGOy9fplzhw3jVzTRyUZTRSZKkMLWcQ/gv0E4aONNqs4P"
    }

    private var groupsV2Ref: MockGroupsV2!
    private var migrationStore: KeyValueStore!
    private var mockDb: MockDB!
    private var versionedProfilesRef: MockVersionedProfiles!
    private var zkParamsMigrator: ZkParamsMigrator!

    override func setUp() {
        super.setUp()

        groupsV2Ref = MockGroupsV2()
        let keyValueStoreFactory = InMemoryKeyValueStoreFactory()
        migrationStore = keyValueStoreFactory.keyValueStore(collection: "GroupsV2Impl.serviceStore")
        mockDb = MockDB()
        versionedProfilesRef = MockVersionedProfiles()
        zkParamsMigrator = ZkParamsMigrator(
            db: mockDb,
            keyValueStoreFactory: keyValueStoreFactory,
            groupsV2: groupsV2Ref,
            profileManager: OWSFakeProfileManager(),
            tsAccountManager: MockTSAccountManager(),
            versionedProfiles: versionedProfilesRef
        )
    }

    func testMigration2022_08_08() throws {
        try XCTSkipUnless(TSConstants.isUsingProductionService)

        mockDb.write { tx in
            // These should not use the constants in case the constants are changed.
            migrationStore.setInt(4, key: "lastZKgroupVersionCounterKey", transaction: tx)
            migrationStore.setString(Constants.serverPublicParams2022_01_03, key: "lastServerPublicParamsKey", transaction: tx)
        }

        zkParamsMigrator.migrateIfNeeded()

        XCTAssertTrue(groupsV2Ref.didClearTemporalCredentials)
        XCTAssertTrue(versionedProfilesRef.didClearProfileKeyCredentials)

        mockDb.read { tx in
            XCTAssertNil(migrationStore.getString(ZkParamsMigrator.Constants.lastServerPublicParamsKey, transaction: tx))
            XCTAssertEqual(
                migrationStore.getInt(ZkParamsMigrator.Constants.lastZkGroupVersionCounterKey, transaction: tx),
                ZkParamsMigrator.Constants.zkGroupMigrationCounter
            )
        }
    }

    func testMigration2023_12_14() throws {
        try XCTSkipUnless(TSConstants.isUsingProductionService)

        mockDb.write { tx in
            // These should not use the constants in case the constants are changed.
            migrationStore.setInt(4, key: "lastZKgroupVersionCounterKey", transaction: tx)
            migrationStore.setString(Constants.serverPublicParams2022_08_08, key: "lastServerPublicParamsKey", transaction: tx)
        }

        zkParamsMigrator.migrateIfNeeded()

        XCTAssertFalse(groupsV2Ref.didClearTemporalCredentials)
        XCTAssertFalse(versionedProfilesRef.didClearProfileKeyCredentials)

        mockDb.read { tx in
            XCTAssertNil(migrationStore.getString(ZkParamsMigrator.Constants.lastServerPublicParamsKey, transaction: tx))
            XCTAssertEqual(
                migrationStore.getInt(ZkParamsMigrator.Constants.lastZkGroupVersionCounterKey, transaction: tx),
                ZkParamsMigrator.Constants.zkGroupMigrationCounter
            )
        }
    }
}
