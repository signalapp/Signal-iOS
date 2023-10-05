//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

// MARK: - Namespace

extension SVR {
    public enum TestMocks {
        public typealias OWS2FAManager = _KeyBackupServiceImpl_OWS2FAManagerTestMock
        public typealias RemoteAttestation = _KeyBackupServiceImpl_RemoteAttestationMock
        public typealias URLSession = _KeyBackupServiceImpl_OWSURLSessionMock
    }
}

// MARK: - OWS2FAManager

public class _KeyBackupServiceImpl_OWS2FAManagerTestMock: SVR.Shims.OWS2FAManager {
    public init() {}

    public var pinCode: String!

    public func pinCode(transaction: DBReadTransaction) -> String? {
        return pinCode
    }

    public func markDisabled(transaction: DBWriteTransaction) {}
}

// MARK: - RemoteAttestation

public class _KeyBackupServiceImpl_RemoteAttestationMock: SVR.Shims.RemoteAttestation {
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

public class _KeyBackupServiceImpl_OWSURLSessionMock: BaseOWSURLSessionMock {

    public var promiseForTSRequestBlock: ((TSRequest) -> Promise<HTTPResponse>)?

    public override func promiseForTSRequest(_ rawRequest: TSRequest) -> Promise<HTTPResponse> {
        return promiseForTSRequestBlock!(rawRequest)
    }
}
