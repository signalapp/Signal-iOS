//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SAMKeychain

public enum KeychainStorageError: Error {
    case failure(description: String)
}

// MARK: -

@objc public protocol KeychainStorage: class {

    @objc func string(forKey key: String, service: String) throws -> String

    @objc func set(string: String, forKey key: String, service: String) throws

    @objc func data(forKey key: String, service: String) throws -> Data

    @objc func set(data: Data, forKey key: String, service: String) throws

    @objc func remove(key: String, service: String) throws
}

// MARK: -

@objc
public class SSKKeychainStorage: NSObject, KeychainStorage {

    @objc public static let sharedInstance = SSKKeychainStorage()

    // Force usage as a singleton
    override private init() {
        super.init()

        SwiftSingletons.register(self)
    }

    @objc public func string(forKey key: String, service: String) throws -> String {
        var error: NSError?
        let result = SAMKeychain.password(forService: service, account: key, error: &error)
        if let error = error {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) error retrieving string: \(error)")
        }
        guard let string = result else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) could not retrieve string")
        }
        return string
    }

    @objc public func set(string: String, forKey key: String, service: String) throws {

        SAMKeychain.setAccessibilityType(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)

        var error: NSError?
        let result = SAMKeychain.setPassword(string, forService: service, account: key, error: &error)
        if let error = error {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) error setting string: \(error)")
        }
        guard result else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) could not set string")
        }
    }

    @objc public func data(forKey key: String, service: String) throws -> Data {
        var error: NSError?
        let result = SAMKeychain.passwordData(forService: service, account: key, error: &error)
        if let error = error {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) error retrieving data: \(error)")
        }
        guard let data = result else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) could not retrieve data")
        }
        return data
    }

    @objc public func set(data: Data, forKey key: String, service: String) throws {

        SAMKeychain.setAccessibilityType(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)

        var error: NSError?
        let result = SAMKeychain.setPasswordData(data, forService: service, account: key, error: &error)
        if let error = error {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) error setting data: \(error)")
        }
        guard result else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) could not set data")
        }
    }

    @objc public func remove(key: String, service: String) throws {
        var error: NSError?
        let result = SAMKeychain.deletePassword(forService: service, account: key, error: &error)
        if let error = error {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) error removing data: \(error)")
        }
        guard result else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) could not remove data")
        }
    }
}
