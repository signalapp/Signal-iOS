//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

open class SVRKeyDeriverMock: SVRKeyDeriver {

    public init() {}

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        tx: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        return .success(data)
    }

    public func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
        tx: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        return .success(encryptedData)
    }

    public var dataGenerator: (SVR.DerivedKey) -> Data? = { _ in return nil }

    public func data(for key: SVR.DerivedKey) -> Data? {
        return dataGenerator(key)
    }

    public func data(for key: SVR.DerivedKey, tx: DBReadTransaction) -> SVR.DerivedKeyData? {
        return SVR.DerivedKeyData(dataGenerator(key), key)
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, tx: DBReadTransaction) -> Bool {
        return true
    }
}

#endif
