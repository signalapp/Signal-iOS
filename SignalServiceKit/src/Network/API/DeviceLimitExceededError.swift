//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public struct DeviceLimitExceededError: LocalizedError {
    init() {}

    init?(_ error: Error) {
        guard error.httpStatusCode == 411 else { return nil }
    }

    public var errorDescription: String? {
        OWSLocalizedString(
            "MULTIDEVICE_PAIRING_MAX_DESC",
            comment: "An error shown as the title of an alert when try to link a new device & the user is already at the limit."
        )
    }

    public var recoverySuggestion: String? {
        OWSLocalizedString(
            "MULTIDEVICE_PAIRING_MAX_RECOVERY",
            comment: "A recovery suggestion shown as the body of an alert when try to link a new device & the user is already at the limit."
        )
    }
}
