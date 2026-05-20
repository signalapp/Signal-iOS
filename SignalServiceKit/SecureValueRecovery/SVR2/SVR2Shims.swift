//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension SVR2 {
    public enum Shims {
        public typealias AppContext = _SVR2_AppContextShim
        public typealias OWS2FAManager = _SVR2_OWS2FAManagerShim
    }

    public enum Wrappers {
        public typealias AppContext = _SVR2_AppContextWrapper
        public typealias OWS2FAManager = _SVR2_OWS2FAManagerWrapper
    }
}

public protocol _SVR2_AppContextShim {

    var isMainApp: Bool { get }
    var isNSE: Bool { get }
}

public class _SVR2_AppContextWrapper: _SVR2_AppContextShim {

    public init() {}

    public var isMainApp: Bool {
        return CurrentAppContext().isMainApp
    }

    public var isNSE: Bool {
        return CurrentAppContext().isNSE
    }
}

// MARK: - OWS2FAManager

public protocol _SVR2_OWS2FAManagerShim {
    func pinCode(transaction: DBReadTransaction) -> String?
    func markDisabled(transaction: DBWriteTransaction)
}

public class _SVR2_OWS2FAManagerWrapper: SVR2.Shims.OWS2FAManager {
    private let manager: OWS2FAManager
    public init(_ manager: OWS2FAManager) { self.manager = manager }

    public func pinCode(transaction: DBReadTransaction) -> String? {
        return manager.pinCode(transaction: transaction)
    }

    public func markDisabled(transaction: DBWriteTransaction) {
        manager.markDisabled(transaction: transaction)
    }
}

#if TESTABLE_BUILD

extension SVR2 {
    enum Mocks {
        typealias AppContext = _SVR2_AppContextMock
    }
}

class _SVR2_AppContextMock: _SVR2_AppContextShim {

    init() {}

    var isMainApp: Bool { true }

    var isNSE: Bool { false }
}

#endif
