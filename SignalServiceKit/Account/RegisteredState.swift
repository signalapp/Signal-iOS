//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct RegisteredState {
    public let isPrimary: Bool
    public let localIdentifiers: LocalIdentifiers

    init(registrationState: TSRegistrationState, localIdentifiers: LocalIdentifiers?) throws(NotRegisteredError) {
        guard registrationState.isRegistered else {
            throw NotRegisteredError()
        }
        // These are both valid when we're registered.
        self.isPrimary = registrationState.isPrimaryDevice!
        self.localIdentifiers = localIdentifiers!
    }
}
