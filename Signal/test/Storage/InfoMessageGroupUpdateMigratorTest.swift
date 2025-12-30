//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import Signal
@testable import SignalServiceKit

class InfoMessageGroupUpdateMigratorTest: SignalBaseTest {

    func testGroupUpdateMigration() async {
        let localIdentifiers: LocalIdentifiers = .forUnitTests
        let localAci = localIdentifiers.aci

        let db = InMemoryDB()
        let modelReadCaches: () -> ModelReadCaches = {
            return ModelReadCaches(factory: ModelReadCacheFactory(appReadiness: AppReadinessMock()))
        }
        let tsAccountManager: () -> TSAccountManager = {
            let mgr = MockTSAccountManager()
            mgr.localIdentifiersMock = { localIdentifiers }
            return mgr
        }

        await db.awaitableWrite { tx in
            insertInfoMessage(infoMessageUserInfo: nil, tx: tx)
            insertInfoMessage(
                infoMessageUserInfo: [
                    .legacyGroupUpdateItems: TSInfoMessage.LegacyPersistableGroupUpdateItemsWrapper(
                        [.inviteRemoved(invitee: ServiceIdUppercaseString(wrappedValue: Pni.randomForTesting()), wasLocalUser: true)],
                    ),
                    .legacyUpdaterKnownToBeLocalUser: false,
                    .groupUpdateSourceLegacyAddress: SignalServiceAddress.isolatedRandomForTesting(),
                ],
                tx: tx,
            )
            insertInfoMessage(infoMessageUserInfo: nil, tx: tx)
            insertInfoMessage(
                infoMessageUserInfo: [.newGroupModel: TSGroupModelV2.forMigrationTest(name: "grüp", localAci: localAci)],
                tx: tx,
            )
            insertInfoMessage(infoMessageUserInfo: nil, tx: tx)
            insertInfoMessage(
                infoMessageUserInfo: [
                    .oldGroupModel: TSGroupModelV2.forMigrationTest(name: "grop", localAci: localAci),
                    .oldDisappearingMessageToken: DisappearingMessageToken(isEnabled: true, durationSeconds: 10),
                    .newGroupModel: TSGroupModelV2.forMigrationTest(name: "grüp", localAci: localAci),
                    .newDisappearingMessageToken: DisappearingMessageToken(isEnabled: true, durationSeconds: 12),
                    .groupUpdateSourceLegacyAddress: SignalServiceAddress.isolatedRandomForTesting(),
                ],
                tx: tx,
            )
            insertInfoMessage(infoMessageUserInfo: nil, tx: tx)
        }

        let migrator = InfoMessageGroupUpdateMigrator(
            db: db,
            modelReadCaches: modelReadCaches,
            tsAccountManager: tsAccountManager,
        )
        try! await migrator.run()

        db.read { tx in
            let infoMessageUserInfoBlobs: [Data] = try! Row.fetchAll(
                tx.database,
                sql: """
                    SELECT infoMessageUserInfo FROM model_TSInteraction
                """,
            ).compactMap { $0["infoMessageUserInfo"] }

            XCTAssertEqual(infoMessageUserInfoBlobs.count, 3)

            for blob in infoMessageUserInfoBlobs {
                let keys = Set(decode(blob).keys)
                XCTAssertEqual(keys, [.groupUpdateItems])
            }
        }
    }

    private func insertInfoMessage(
        infoMessageUserInfo: [InfoMessageUserInfoKey: Any]?,
        tx: DBWriteTransaction,
    ) {
        try! tx.database.execute(
            sql: """
                INSERT INTO model_TSInteraction
                (recordType, uniqueId, receivedAtTimestamp, timestamp, uniqueThreadId, infoMessageUserInfo)
                VALUES (?, ?, 0, 0, ?, ?)
            """,
            arguments: [SDSRecordType.infoMessage.rawValue, UUID().uuidString, UUID().uuidString, infoMessageUserInfo.map { encode($0) }],
        )
    }

    private func encode(_ infoMessageUserInfo: [InfoMessageUserInfoKey: Any]) -> Data {
        return try! NSKeyedArchiver.archivedData(
            withRootObject: infoMessageUserInfo,
            requiringSecureCoding: false,
        )
    }

    private func decode(_ data: Data) -> [InfoMessageUserInfoKey: Any] {
        return try! NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSDictionary.self,
            from: data,
            requiringSecureCoding: false,
        ) as! [InfoMessageUserInfoKey: Any]
    }
}

// MARK: -

private extension TSGroupModelV2 {
    static func forMigrationTest(
        name: String,
        localAci: Aci,
    ) -> TSGroupModelV2 {
        return TSGroupModelV2(
            groupId: Data(repeating: 8, count: 32),
            name: name,
            descriptionText: nil,
            avatarDataState: .missing,
            groupMembership: GroupMembership(membersForTest: [SignalServiceAddress.isolatedForTesting(serviceId: localAci)]),
            groupAccess: .defaultForV2,
            revision: 3,
            secretParamsData: Data(repeating: 9, count: 10),
            avatarUrlPath: nil,
            inviteLinkPassword: nil,
            isAnnouncementsOnly: false,
            isJoinRequestPlaceholder: false,
            wasJustMigrated: false,
            didJustAddSelfViaGroupLink: false,
            addedByAddress: nil,
        )
    }
}
