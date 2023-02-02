//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

// MARK: - Namespace

extension KBS {
    public enum TestMocks {
        public typealias TSAccountManager = _KeyBackupService_TSAccountManagerTestMock
        public typealias StorageServiceManager = _KeyBackupService_StorageServiceManagerTestMock
        public typealias OWS2FAManager = _KeyBackupService_OWS2FAManagerTestMock
    }
}

// MARK: - TSAccountManager

public class _KeyBackupService_TSAccountManagerTestMock: KBS.Shims.TSAccountManager {

    public init() {}

    public var isPrimaryDevice: Bool = true

    public func isPrimaryDevice(transaction: DBReadTransaction) -> Bool {
        return isPrimaryDevice
    }

    public var isRegisteredAndReady: Bool = true

    public func isRegisteredAndReady(transaction: DBReadTransaction) -> Bool {
        return isRegisteredAndReady
    }
}

// MARK: - StorageServiceManager

public class _KeyBackupService_StorageServiceManagerTestMock: KBS.Shims.StorageServiceManager {

    public init() {}

    public func resetLocalData(transaction: DBWriteTransaction) {}

    public func restoreOrCreateManifestIfNecessary() {}
}

// MARK: - OWS2FAManager

public class _KeyBackupService_OWS2FAManagerTestMock: KBS.Shims.OWS2FAManager {
    public init() {}

    public var pinCode: String!

    public func pinCode(transaction: DBReadTransaction) -> String? {
        return pinCode
    }

    public func markDisabled(transaction: DBWriteTransaction) {}
}
