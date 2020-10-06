//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class KeyBackupServiceTests: SSKBaseTestSwift {
    lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dataDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let data = Data.data(fromHex: string) else { throw OWSAssertionError("Invalid data") }
            return data
        }
        return decoder
    }()

    func test_vectors() throws {
        struct Vector: Codable {
            let pin: String
            let backupId: Data
            let argon2Hash: Data
            let masterKey: Data
            let kbsAccessKey: Data
            let ivAndCipher: Data
            let registrationLock: String
        }

        let vectorsUrl = Bundle(for: type(of: self)).url(forResource: "kbs_vectors", withExtension: "json")!
        let jsonData = try Data(contentsOf: vectorsUrl)
        let vectors = try decoder.decode([Vector].self, from: jsonData)

        for vector in vectors {
            let (encryptionKey, accessKey) = try KeyBackupService.deriveEncryptionKeyAndAccessKey(pin: vector.pin, backupId: vector.backupId)

            XCTAssertEqual(vector.argon2Hash, encryptionKey + accessKey)
            XCTAssertEqual(vector.kbsAccessKey, accessKey)

            let ivAndCipher = try KeyBackupService.encryptMasterKey(vector.masterKey, encryptionKey: encryptionKey)

            XCTAssertEqual(vector.ivAndCipher, ivAndCipher)

            let decryptedMasterKey = try KeyBackupService.decryptMasterKey(ivAndCipher, encryptionKey: encryptionKey)

            XCTAssertEqual(vector.masterKey, decryptedMasterKey)

            databaseStorage.write { transaction in
                KeyBackupService.store(
                    masterKey: vector.masterKey,
                    isMasterKeyBackedUp: true,
                    pinType: .init(forPin: vector.pin),
                    encodedVerificationString: "",
                    enclaveName: "",
                    transaction: transaction
                )
            }

            let registrationLockToken = KeyBackupService.deriveRegistrationLockToken()

            XCTAssertEqual(vector.registrationLock, registrationLockToken)
        }
    }

    func test_pinNormalization() throws {
        struct Vector: Codable {
            let name: String
            let pin: String
            let bytes: Data
        }

        let vectorsUrl = Bundle(for: type(of: self)).url(forResource: "kbs_pin_sanitation_vectors", withExtension: "json")!
        let jsonData = try Data(contentsOf: vectorsUrl)
        let vectors = try decoder.decode([Vector].self, from: jsonData)

        for vector in vectors {
            let normalizedPin = KeyBackupService.normalizePin(vector.pin)
            XCTAssertEqual(vector.bytes, normalizedPin.data(using: .utf8)!, vector.name)
        }
    }

    func test_pinVerification() throws {
        let pin = "apassword"
        let salt = Data.data(
            fromHex: "202122232425262728292A2B2C2D2E2F"
        )!
        let expectedEncodedVerificationString = "$argon2i$v=19$m=512,t=64,p=1$ICEiIyQlJicoKSorLC0uLw$NeZzhiNv4cRmRMct9scf7d838bzmHJvrZtU/0BH0v/U"

        let encodedVerificationString = try KeyBackupService.deriveEncodedVerificationString(pin: pin, salt: salt)

        XCTAssertEqual(expectedEncodedVerificationString, encodedVerificationString)

        databaseStorage.write { transaction in
            KeyBackupService.store(
                masterKey: Data(repeating: 0x00, count: 32),
                isMasterKeyBackedUp: true,
                pinType: .init(forPin: pin),
                encodedVerificationString: encodedVerificationString,
                enclaveName: "",
                transaction: transaction
            )
        }

        // The correct PIN returns as valid.
        AssertPin(pin, isValid: true)

        // The incorrect PIN returns as invalid.
        AssertPin("notmypassword", isValid: false)
    }

    func test_storageServiceEncryption() throws {
        struct Vector: Codable {
            enum VectorType: String, Codable {
                case storageServiceManifest
                case storageServiceRecord
            }
            let type: VectorType

            enum VectorMode: String, Codable {
                case local
                case synced
            }
            let mode: VectorMode

            let masterKeyData: Data?
            let storageServiceKeyData: Data
            let derivedKeyData: Data
            let associatedValueData: Data
            let rawData: Data
            let encryptedData: Data

            var derivedKey: KeyBackupService.DerivedKey {
                switch type {
                case .storageServiceRecord:
                    return .storageServiceRecord(identifier: StorageService.StorageIdentifier(data: associatedValueData, type: .contact))
                case .storageServiceManifest:
                    return .storageServiceManifest(version: associatedValueData.withUnsafeBytes { $0.pointee })
                }
            }

            func storeKey(transaction: SDSAnyWriteTransaction) {
                KeyBackupService.clearKeys(transaction: transaction)
                switch mode {
                case .local:
                    KeyBackupService.store(
                        masterKey: masterKeyData!,
                        isMasterKeyBackedUp: true,
                        pinType: .numeric,
                        encodedVerificationString: "",
                        enclaveName: "",
                        transaction: transaction
                    )
                case .synced:
                    KeyBackupService.storeSyncedKey(type: .storageService, data: storageServiceKeyData, transaction: transaction)
                }
            }
        }

        let vectorsUrl = Bundle(for: type(of: self)).url(forResource: "kbs_storage_service_encryption_vectors", withExtension: "json")!
        let jsonData = try Data(contentsOf: vectorsUrl)
        let vectors = try decoder.decode([Vector].self, from: jsonData)

        for vector in vectors {
            databaseStorage.write { vector.storeKey(transaction: $0) }

            XCTAssertEqual(KeyBackupService.hasMasterKey, vector.masterKeyData != nil)

            XCTAssertEqual(vector.derivedKeyData, vector.derivedKey.data)
            XCTAssertEqual(vector.storageServiceKeyData, KeyBackupService.DerivedKey.storageService.data)

            let encryptedData = try KeyBackupService.encrypt(keyType: vector.derivedKey, data: vector.rawData)
            let decryptedData = try KeyBackupService.decrypt(keyType: vector.derivedKey, encryptedData: encryptedData)
            XCTAssertEqual(vector.rawData, decryptedData)

            let decryptedVectorData = try KeyBackupService.decrypt(keyType: vector.derivedKey, encryptedData: vector.encryptedData)
            XCTAssertEqual(vector.rawData, decryptedVectorData)
        }
    }

    func AssertPin(
        _ pin: String,
        isValid expectedResult: Bool,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let expectation = XCTestExpectation(description: "Verify Pin")
        KeyBackupService.verifyPin(pin) { isValid in
            XCTAssertEqual(isValid, expectedResult, message, file: file, line: line)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}
