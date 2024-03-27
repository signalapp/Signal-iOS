//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSAccountManagerImpl {
    public enum Shims {
        public typealias AppReadiness = _TSAccountManagerImpl_AppReadinessShim
    }

    public enum Wrappers {
        public typealias AppReadiness = _TSAccountManagerImpl_AppReadinessWrapper
    }
}

public protocol _TSAccountManagerImpl_AppReadinessShim {

    var isMainApp: Bool { get }

    func runNowOrWhenAppDidBecomeReadyAsync(_ block: @escaping () -> Void)
}

public class _TSAccountManagerImpl_AppReadinessWrapper: _TSAccountManagerImpl_AppReadinessShim {

    public init() {}

    public var isMainApp: Bool {
        return CurrentAppContext().isMainApp
    }

    public func runNowOrWhenAppDidBecomeReadyAsync(_ block: @escaping () -> Void) {
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync(block)
    }
}
