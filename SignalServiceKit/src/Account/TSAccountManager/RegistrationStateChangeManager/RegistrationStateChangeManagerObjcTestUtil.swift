//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

@objcMembers
public class RegistrationStateChangeManagerObjcTestUtil: NSObject {

    private override init() { super.init() }

    public static func registerForTests(
        localNumber: String,
        aci: UUID
    ) {
        DependenciesBridge.shared.db.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as? RegistrationStateChangeManagerImpl)?.registerForTests(
                localIdentifiers: .init(aci: .init(fromUUID: aci), pni: nil, phoneNumber: localNumber),
                tx: tx
            )
        }
    }
}

#endif
