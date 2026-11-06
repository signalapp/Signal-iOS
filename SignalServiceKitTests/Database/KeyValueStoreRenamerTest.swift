//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

struct KeyValueStoreRenamerTest {
    @Test
    func testRenamer() throws {
        let db = InMemoryDB()
        let oldCollection = NewKeyValueStore(collection: "A")
        db.write { tx in
            oldCollection.writeValue("World", forKey: "Hello", tx: tx)
        }
        try db.write { tx in
            let renamer = KeyValueStoreRenamer(oldCollection: "A", newCollection: "B")
            try renamer.renameKey("Hello", toKey: "Hi", tx: tx)
        }
        let newCollection = NewKeyValueStore(collection: "B")
        let newValue = db.read { tx in newCollection.fetchValue(String.self, forKey: "Hi", tx: tx) }
        #expect(newValue == "World")
    }
}
