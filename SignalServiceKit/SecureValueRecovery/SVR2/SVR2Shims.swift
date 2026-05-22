//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension SVR2 {
    public enum Shims {
        public typealias OWS2FAManager = _SVR2_OWS2FAManagerShim
    }

    public enum Wrappers {
        public typealias OWS2FAManager = _SVR2_OWS2FAManagerWrapper
    }
}

// MARK: - OWS2FAManager

public protocol _SVR2_OWS2FAManagerShim {
    func pinCode(transaction: DBReadTransaction) -> String?
}

public class _SVR2_OWS2FAManagerWrapper: SVR2.Shims.OWS2FAManager {
    private let manager: OWS2FAManager
    public init(_ manager: OWS2FAManager) { self.manager = manager }

    public func pinCode(transaction: DBReadTransaction) -> String? {
        return manager.pinCode(transaction: transaction)
    }
}
