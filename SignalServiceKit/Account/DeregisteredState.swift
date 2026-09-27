//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DeregisteredState {
    public let isPrimary: Bool
    public let localIdentifiers: DeregisteredLocalIdentifiers

    init?(registrationState: TSRegistrationState) {
        switch registrationState {
        case .deregistered(let localIdentifiers):
            self.isPrimary = true
            self.localIdentifiers = localIdentifiers
        case .delinked(let localIdentifiers):
            self.isPrimary = false
            self.localIdentifiers = localIdentifiers
        case .unregistered, .reregistering, .relinking, .registered, .provisioned, .transferringIncoming, .transferringPrimaryOutgoing, .transferringLinkedOutgoing, .transferred:
            return nil
        }
    }
}
