//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum SMKError: Error {
    case assertionError(description: String)
    case invalidInput(_ description: String)
}
