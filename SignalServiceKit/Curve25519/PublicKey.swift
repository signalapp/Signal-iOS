//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension PublicKey {
    public convenience init(keyData: Data) throws {
        try self.init([Constants.keyTypeDJB] + keyData)
    }

    public enum Constants {
        public static let keyTypeDJB: UInt8 = 0x05
    }
}
