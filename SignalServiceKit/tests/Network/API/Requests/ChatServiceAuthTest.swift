//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class ChatServiceAuthTest: XCTestCase {
    func testImplicit() {
        let auth = ChatServiceAuth.implicit()

        XCTAssertEqual(auth.credentials, .implicit)
    }

    func testExplicit() {
        let uuidString = "125A6D22-5364-4583-9132-66227867D9EC"
        let aci = UUID(uuidString: uuidString)!

        let auth = ChatServiceAuth.explicit(aci: aci, password: "foo bar")

        XCTAssertEqual(auth.credentials, .explicit(username: uuidString, password: "foo bar"))
    }

    func testEquality() {
        let uuid1 = UUID()
        let uuid2 = UUID()

        let implicit = ChatServiceAuth.implicit()
        let explicit1 = ChatServiceAuth.explicit(aci: uuid1, password: "foo bar")
        let explicit2 = ChatServiceAuth.explicit(aci: uuid1, password: "foo bar")
        let explicit3 = ChatServiceAuth.explicit(aci: uuid1, password: "baz qux")
        let explicit4 = ChatServiceAuth.explicit(aci: uuid2, password: "foo bar")

        for auth in [implicit, explicit1, explicit2, explicit3, explicit4] {
            XCTAssertEqual(auth, auth)
        }

        for other in [explicit1, explicit2, explicit3, explicit4] {
            XCTAssertNotEqual(implicit, other)
            XCTAssertNotEqual(other, implicit)
        }

        XCTAssertEqual(explicit1, explicit2)
        XCTAssertNotEqual(explicit1, explicit3)
        XCTAssertNotEqual(explicit1, explicit4)
    }
}
