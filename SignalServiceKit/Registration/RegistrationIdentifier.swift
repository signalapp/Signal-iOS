//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An identifier for a pre-existing account used during registration.
public enum RegistrationIdentifier {
    case phoneNumber(E164)
}
