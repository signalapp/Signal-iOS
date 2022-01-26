//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalClient

public extension UUID {
    var data: Data {
        return withUnsafeBytes(of: self.uuid, { Data($0) })
    }
}

// MARK: -

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
