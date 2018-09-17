//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SAMKeychain

public enum KeychainStorageError: Error {
    case failure(description: String)
}

// MARK: -

@objc public protocol SSKKeychainStorage: class {

    @objc func string(forService service: String, key: String) throws -> String

    @objc(setString:service:key:error:) func set(string: String, service: String, key: String) throws

    @objc func data(forService service: String, key: String) throws -> Data

    @objc func set(data: Data, service: String, key: String) throws

    @objc func remove(service: String, key: String) throws
}

// MARK: -

@objc
public class SSKDefaultKeychainStorage: NSObject, SSKKeychainStorage {

    @objc public static let shared = SSKDefaultKeychainStorage()

    // Force usage as a singleton
    override private init() {
        super.init()

        SwiftSingletons.register(self)
    }

    @objc public func string(forService service: String, key: String) throws -> String {
        var error: NSError?
        let result = SAMKeychain.password(forService: service, account: key, error: &error)
        if let error = error {
            throw KeychainStorageError.failure(description: "\(logTag) error retrieving string: \(error)")
        }
        guard let string = result else {
            throw KeychainStorageError.failure(description: "\(logTag) could not retrieve string")
        }
        return string
    }

    @objc public func set(string: String, service: String, key: String) throws {

        SAMKeychain.setAccessibilityType(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)

        var error: NSError?
        let result = SAMKeychain.setPassword(string, forService: service, account: key, error: &error)
        if let error = error {
            throw KeychainStorageError.failure(description: "\(logTag) error setting string: \(error)")
        }
        guard result else {
            throw KeychainStorageError.failure(description: "\(logTag) could not set string")
        }
    }

    @objc public func data(forService service: String, key: String) throws -> Data {
        var error: NSError?
        let result = SAMKeychain.passwordData(forService: service, account: key, error: &error)
        if let error = error {
            throw KeychainStorageError.failure(description: "\(logTag) error retrieving data: \(error)")
        }
        guard let data = result else {
            throw KeychainStorageError.failure(description: "\(logTag) could not retrieve data")
        }
        return data
    }

    @objc public func set(data: Data, service: String, key: String) throws {

        SAMKeychain.setAccessibilityType(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)

        var error: NSError?
        let result = SAMKeychain.setPasswordData(data, forService: service, account: key, error: &error)
        if let error = error {
            throw KeychainStorageError.failure(description: "\(logTag) error setting data: \(error)")
        }
        guard result else {
            throw KeychainStorageError.failure(description: "\(logTag) could not set data")
        }
    }

    @objc public func remove(service: String, key: String) throws {
        var error: NSError?
        let result = SAMKeychain.deletePassword(forService: service, account: key, error: &error)
        if let error = error {
            // If deletion failed because the specified item could not be found in the keychain, consider it success.
            if error.code == errSecItemNotFound {
                Logger.info("Keychain delete failed; item not found.")
                return
            }
            throw KeychainStorageError.failure(description: "\(logTag) error removing data: \(error)")
        }
        guard result else {
            throw KeychainStorageError.failure(description: "\(logTag) could not remove data")
        }
    }
}
