//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

open class MasterKeyMock: MasterKey {

    public var rawData: Data { Data() }

    public init() {}

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data
    ) -> SVR.ApplyDerivedKeyResult {
        return .success(data)
    }

    public func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data
    ) -> SVR.ApplyDerivedKeyResult {
        return .success(encryptedData)
    }

    public var dataGenerator: (SVR.DerivedKey) -> Data = { _ in return Data() }

    public func data(for key: SVR.DerivedKey) -> SVR.DerivedKeyData {
        return SVR.DerivedKeyData(rawData: dataGenerator(key), type: key)
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, tx: DBReadTransaction) -> Bool {
        return true
    }
}

#endif
