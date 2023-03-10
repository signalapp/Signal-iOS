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
        public typealias RemoteAttestation = _KeyBackupService_RemoteAttestationMock
        public typealias URLSession = _KeyBackupService_OWSURLSessionMock
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

    public func restoreOrCreateManifestIfNecessary(authedAccount: AuthedAccount) {}
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

// MARK: - RemoteAttestation

public class _KeyBackupService_RemoteAttestationMock: KBS.Shims.RemoteAttestation {
    public init() {}

    var authMethodInputs = [RemoteAttestation.KeyBackupAuthMethod]()
    var enclaveInputs = [KeyBackupEnclave]()

    var promisesToReturn = [Promise<RemoteAttestation>]()

    public func performForKeyBackup(
        authMethod: RemoteAttestation.KeyBackupAuthMethod,
        enclave: KeyBackupEnclave
    ) -> Promise<RemoteAttestation> {
        authMethodInputs.append(authMethod)
        enclaveInputs.append(enclave)
        return promisesToReturn.remove(at: 0)
    }
}

// MARK: - OWSURLSession

public class _KeyBackupService_OWSURLSessionMock: BaseOWSURLSessionMock {

    public var promiseForTSRequestBlock: ((TSRequest) -> Promise<HTTPResponse>)?

    public override func promiseForTSRequest(_ rawRequest: TSRequest) -> Promise<HTTPResponse> {
        return promiseForTSRequestBlock!(rawRequest)
    }
}
