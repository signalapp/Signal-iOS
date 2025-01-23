//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

extension GroupIdentifier {
    public var logString: String {
        return "g\(self.serialize().asData.base64EncodedString())"
    }
}
