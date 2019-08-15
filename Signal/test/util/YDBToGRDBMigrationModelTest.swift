//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit
@testable import SignalMessaging

class YDBToGRDBMigrationModelTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func randomStickerPackInfo() -> StickerPackInfo {
        let packId = Randomness.generateRandomBytes(16)
        let packKey = Randomness.generateRandomBytes(Int32(StickerManager.packKeyLength))

        return StickerPackInfo(packId: packId, packKey: packKey)
    }

    func randomKnownStickerPack() -> KnownStickerPack {
        return KnownStickerPack(info: randomStickerPackInfo())
    }

    func testKnownStickerPack() {
        let model1 = randomKnownStickerPack()
        let model2 = randomKnownStickerPack()
        let model3 = randomKnownStickerPack()

        self.yapRead { transaction in
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction.asAnyRead))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction.asAnyRead))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction.asAnyRead))
            XCTAssertEqual(0, KnownStickerPack.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction))
            XCTAssertEqual(0, KnownStickerPack.anyCount(transaction: transaction))
        }

        self.yapWrite { transaction in
            model1.anyInsert(transaction: transaction.asAnyWrite)
            model2.anyInsert(transaction: transaction.asAnyWrite)
            // Don't insert 3.
        }

        self.yapRead { transaction in
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction.asAnyRead))
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction.asAnyRead))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction.asAnyRead))
            XCTAssertEqual(2, KnownStickerPack.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction))
            XCTAssertEqual(0, KnownStickerPack.anyCount(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBUnorderedRecordMigrator<KnownStickerPack>(label: "KnownStickerPack", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.yapRead { transaction in
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction.asAnyRead))
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction.asAnyRead))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction.asAnyRead))
            XCTAssertEqual(2, KnownStickerPack.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction))
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction))
            XCTAssertEqual(2, KnownStickerPack.anyCount(transaction: transaction))
        }
    }
}
