//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class ZkParamsMigratorTest: XCTestCase {
    private enum Constants {
        static let serverPublicParams2022_08_08 = "AMhf5ywVwITZMsff/eCyudZx9JDmkkkbV6PInzG4p8x3VqVJSFiMvnvlEKWuRob/1eaIetR31IYeAbm0NdOuHH8Qi+Rexi1wLlpzIo1gstHWBfZzy1+qHRV5A4TqPp15YzBPm0WSggW6PbSn+F4lf57VCnHF7p8SvzAA2ZZJPYJURt8X7bbg+H3i+PEjH9DXItNEqs2sNcug37xZQDLm7X36nOoGPs54XsEGzPdEV+itQNGUFEjY6X9Uv+Acuks7NpyGvCoKxGwgKgE5XyJ+nNKlyHHOLb6N1NuHyBrZrgtY/JYJHRooo5CEqYKBqdFnmbTVGEkCvJKxLnjwKWf+fEPoWeQFj5ObDjcKMZf2Jm2Ae69x+ikU5gBXsRmoF94GXTLfN0/vLt98KDPnxwAQL9j5V1jGOY8jQl6MLxEs56cwXN0dqCnImzVH3TZT1cJ8SW1BRX6qIVxEzjsSGx3yxF3suAilPMqGRp4ffyopjMD1JXiKR2RwLKzizUe5e8XyGOy9fplzhw3jVzTRyUZTRSZKkMLWcQ/gv0E4aONNqs4P"
    }

    private var authCredentialStore: AuthCredentialStore!
    private var migrationStore: KeyValueStore!
    private var mockDb: InMemoryDB!
    private var versionedProfilesRef: MockVersionedProfiles!
    private var zkParamsMigrator: ZkParamsMigrator!

    override func setUp() {
        super.setUp()

        authCredentialStore = AuthCredentialStore()
        migrationStore = KeyValueStore(collection: "GroupsV2Impl.serviceStore")
        mockDb = InMemoryDB()
        versionedProfilesRef = MockVersionedProfiles()
        zkParamsMigrator = ZkParamsMigrator(
            appReadiness: AppReadinessMock(),
            authCredentialStore: authCredentialStore,
            db: mockDb,
            profileManager: OWSFakeProfileManager(),
            tsAccountManager: MockTSAccountManager(),
            versionedProfiles: versionedProfilesRef,
        )

        let groupAuthCredentialStore = KeyValueStore(collection: "GroupsV2Impl.authCredentialStoreStore")
        mockDb.write { tx in
            groupAuthCredentialStore.setData(Data(), key: "0", transaction: tx)
        }
    }

    func testMigrationV4() throws {
        try XCTSkipUnless(TSConstants.isUsingProductionService)

        mockDb.write { tx in
            // These should not use the constants in case the constants are changed.
            migrationStore.setInt(4, key: "lastZKgroupVersionCounterKey", transaction: tx)
            migrationStore.setString(Constants.serverPublicParams2022_08_08, key: "lastServerPublicParamsKey", transaction: tx)
        }

        zkParamsMigrator.migrateIfNeeded()

        try mockDb.read { tx in
            XCTAssertNil(try authCredentialStore.groupAuthCredential(for: 0, tx: tx))
        }
        XCTAssertTrue(versionedProfilesRef.didClearProfileKeyCredentials)

        mockDb.read { tx in
            XCTAssertNil(migrationStore.getString(ZkParamsMigrator.Constants.lastServerPublicParamsKey, transaction: tx))
            XCTAssertEqual(
                migrationStore.getInt(ZkParamsMigrator.Constants.lastZkGroupVersionCounterKey, transaction: tx),
                ZkParamsMigrator.Constants.zkGroupMigrationCounter,
            )
        }
    }
}
