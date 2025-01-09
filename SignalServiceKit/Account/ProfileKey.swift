//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
import Foundation

extension ProfileKey {
    public convenience init(_ profileKey: Aes256Key) {
        // The force unwrap is safe because Aes256Key requires keyData to be 32
        // bytes, and ProfileKey requires its content to be 32 bytes.
        try! self.init(contents: [UInt8](profileKey.keyData))
    }
}
