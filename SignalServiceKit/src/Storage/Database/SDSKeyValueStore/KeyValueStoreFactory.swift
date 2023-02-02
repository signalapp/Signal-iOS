//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Classes that require a `KeyValueStoreProtocol` instance should
/// accept a `KeyValueStoreFactory` as an explicit dependency, and use it
/// to generate key value store instances.
///
/// This allows stubbing things out in tests; in production code, a provided `SDSKeyValueStoreFactory`
/// instance will produce key value stores backed by GRDB. In tests, an in memory factory instance
/// will let code under test read and write without setting up a database.
public protocol KeyValueStoreFactory {

    func keyValueStore(collection: String) -> KeyValueStoreProtocol
}

/// Produces `KeyValueStoreProtocol` instances backed by GRDB (`SDSKeyValueStore`s).
public class SDSKeyValueStoreFactory: KeyValueStoreFactory {

    public init() {}

    public func keyValueStore(collection: String) -> KeyValueStoreProtocol {
        return SDSKeyValueStore(collection: collection)
    }
}
