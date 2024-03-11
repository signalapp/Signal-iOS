//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

@objcMembers
public class RegistrationStateChangeManagerObjcTestUtil: NSObject {

    private override init() { super.init() }

    public static func registerForTests() {
        DependenciesBridge.shared.db.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as? RegistrationStateChangeManagerImpl)?.registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx
            )
        }
    }
}

#endif
