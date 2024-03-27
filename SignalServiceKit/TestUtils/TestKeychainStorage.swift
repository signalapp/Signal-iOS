//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

@objc
public class SSKTestKeychainStorage: NSObject, SSKKeychainStorage {

    private let lock = UnfairLock()
    private var dataMap = [String: Data]()

    @objc
    public override init() {
        super.init()
    }

    @objc
    public func string(forService service: String, key: String) throws -> String {
        let data = try self.data(forService: service, key: key)
        guard let string = String(bytes: data, encoding: String.Encoding.utf8) else {
            throw KeychainStorageError.failure(description: "\(logTag) could not retrieve string")
        }
        return string
    }

    @objc
    public func set(string: String, service: String, key: String) throws {
        guard let data = string.data(using: String.Encoding.utf8) else {
            throw KeychainStorageError.failure(description: "\(logTag) could not store data")
        }
        try set(data: data, service: service, key: key)
    }

    private func key(forService service: String, key: String) -> String {
        return "\(service) \(key)"
    }

    @objc
    public func data(forService service: String, key: String) throws -> Data {
        try lock.withLock {
            let key = self.key(forService: service, key: key)
            guard let data = dataMap[key] else {
                throw KeychainStorageError.failure(description: "\(logTag) could not retrieve data")
            }
            return data
        }
    }

    @objc
    public func set(data: Data, service: String, key: String) throws {
        lock.withLock {
            let key = self.key(forService: service, key: key)
            dataMap[key] = data
        }
    }

    @objc
    public func remove(service: String, key: String) throws {
        lock.withLock {
            let key = self.key(forService: service, key: key)
            dataMap.removeValue(forKey: key)
        }
    }
}

#endif
