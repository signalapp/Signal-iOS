//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum RegistrationMode: Codable, Equatable {
    case registering
    case reRegistering(e164: String)
    case changingNumber(oldE164: String, oldAuthToken: String)
}
