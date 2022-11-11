//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import LibSignalClient

public extension ProfileKeyVersion {
    // GroupsV2 TODO: We might move this to the wrappers.
    func asHexadecimalString() throws -> String {
        let profileKeyVersionData = serialize().asData
        // A peculiarity of ProfileKeyVersion is that its contents
        // are an ASCII-encoded hexadecimal string of the profile key
        // version, rather than the raw version bytes.
        guard let profileKeyVersionString = String(data: profileKeyVersionData, encoding: .ascii) else {
            throw OWSAssertionError("Invalid profile key version.")
        }
        return profileKeyVersionString
    }
}
