//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct RegisteredState {
    public let isPrimary: Bool
    public let localIdentifiers: LocalIdentifiers

    init(registrationState: TSRegistrationState) throws(NotRegisteredError) {
        switch registrationState {
        case .registered(let localIdentifiers):
            self.isPrimary = true
            self.localIdentifiers = localIdentifiers
        case .provisioned(let localIdentifiers):
            self.isPrimary = false
            self.localIdentifiers = localIdentifiers
        case .unregistered, .reregistering, .relinking, .deregistered, .delinked, .transferringIncoming, .transferringPrimaryOutgoing, .transferringLinkedOutgoing, .transferred:
            throw NotRegisteredError()
        }
    }
}
