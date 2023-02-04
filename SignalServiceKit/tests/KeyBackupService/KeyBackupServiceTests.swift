//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class KeyBackupServiceTests: XCTestCase {

    private var db: MockDB!
    private var keyBackupService: KeyBackupService!

    private var credentialStorage: KBSAuthCredentialStorageMock!
    private var remoteAttestation: KBS.TestMocks.RemoteAttestation!
    private var mockSignalService: OWSSignalServiceMock!
    private var tsConstants: TSConstantsProtocol!

    override func setUp() {
        self.db = MockDB()
        self.credentialStorage = KBSAuthCredentialStorageMock()
        self.remoteAttestation = KBS.TestMocks.RemoteAttestation()
        self.mockSignalService = OWSSignalServiceMock()
        self.tsConstants = TSConstants.shared
        self.keyBackupService = KeyBackupService(
            accountManager: KBS.TestMocks.TSAccountManager(),
            appContext: TestAppContext(),
            credentialStorage: credentialStorage,
            databaseStorage: db,
            keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
            remoteAttestation: remoteAttestation,
            signalService: mockSignalService,
            storageServiceManager: KBS.TestMocks.StorageServiceManager(),
            syncManager: OWSMockSyncManager(),
            tsConstants: tsConstants,
            twoFAManager: KBS.TestMocks.OWS2FAManager()
        )
    }

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
            let (encryptionKey, accessKey) = try keyBackupService.deriveEncryptionKeyAndAccessKey(pin: vector.pin, backupId: vector.backupId)

            XCTAssertEqual(vector.argon2Hash, encryptionKey + accessKey)
            XCTAssertEqual(vector.kbsAccessKey, accessKey)

            let ivAndCipher = try keyBackupService.encryptMasterKey(vector.masterKey, encryptionKey: encryptionKey)

            XCTAssertEqual(vector.ivAndCipher, ivAndCipher)

            let decryptedMasterKey = try keyBackupService.decryptMasterKey(ivAndCipher, encryptionKey: encryptionKey)

            XCTAssertEqual(vector.masterKey, decryptedMasterKey)

            db.write { transaction in
                keyBackupService.store(
                    masterKey: vector.masterKey,
                    isMasterKeyBackedUp: true,
                    pinType: .init(forPin: vector.pin),
                    encodedVerificationString: "",
                    enclaveName: "",
                    transaction: transaction
                )
            }

            let registrationLockToken = keyBackupService.deriveRegistrationLockToken()

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

        let encodedVerificationString = try keyBackupService.deriveEncodedVerificationString(pin: pin, salt: salt)

        XCTAssertEqual(expectedEncodedVerificationString, encodedVerificationString)

        db.write { transaction in
            keyBackupService.store(
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

            var derivedKey: KBS.DerivedKey {
                switch type {
                case .storageServiceRecord:
                    return .storageServiceRecord(identifier: StorageService.StorageIdentifier(data: associatedValueData, type: .contact))
                case .storageServiceManifest:
                    return .storageServiceManifest(version: associatedValueData.withUnsafeBytes { $0.pointee })
                }
            }

            func storeKey(keyBackupService: KeyBackupService, transaction: DBWriteTransaction) {
                keyBackupService.clearKeys(transaction: transaction)
                switch mode {
                case .local:
                    keyBackupService.store(
                        masterKey: masterKeyData!,
                        isMasterKeyBackedUp: true,
                        pinType: .numeric,
                        encodedVerificationString: "",
                        enclaveName: "",
                        transaction: transaction
                    )
                case .synced:
                    keyBackupService.storeSyncedKey(type: .storageService, data: storageServiceKeyData, transaction: transaction)
                }
            }
        }

        let vectorsUrl = Bundle(for: type(of: self)).url(forResource: "kbs_storage_service_encryption_vectors", withExtension: "json")!
        let jsonData = try Data(contentsOf: vectorsUrl)
        let vectors = try decoder.decode([Vector].self, from: jsonData)

        for vector in vectors {
            db.write { vector.storeKey(keyBackupService: keyBackupService, transaction: $0) }

            XCTAssertEqual(keyBackupService.hasMasterKey, vector.masterKeyData != nil)

            XCTAssertEqual(vector.derivedKeyData, keyBackupService.data(for: vector.derivedKey))
            XCTAssertEqual(vector.storageServiceKeyData, keyBackupService.data(for: .storageService))

            let encryptedData = try keyBackupService.encrypt(keyType: vector.derivedKey, data: vector.rawData)
            let decryptedData = try keyBackupService.decrypt(keyType: vector.derivedKey, encryptedData: encryptedData)
            XCTAssertEqual(vector.rawData, decryptedData)

            let decryptedVectorData = try keyBackupService.decrypt(keyType: vector.derivedKey, encryptedData: vector.encryptedData)
            XCTAssertEqual(vector.rawData, decryptedVectorData)
        }
    }

    func test_kbsCredentialStorage() throws {
        let firstCredential = KBSAuthCredential(credential: .init(username: "abc", password: "123"))
        remoteAttestation.promisesToReturn.append(.value(fakeRemoteAttestation(firstCredential)))

        // Try once without auth, and with a success response.
        var promise: Promise<RemoteAttestation> = keyBackupService.performRemoteAttestation(auth: nil, enclave: tsConstants.keyBackupEnclave)
        var expectation = self.expectation(description: "noAuth")
        promise.observe {
            expectation.fulfill()
            switch $0 {
            case .success:
                break
            case .failure(let error):
                XCTFail("\(error)")
            }
        }
        wait(for: [expectation], timeout: 10)

        // Input should be empty.
        XCTAssertEqual(remoteAttestation.authCredentialInputs, [nil])

        // Check that auth has been stored.
        XCTAssertEqual(credentialStorage.dict[firstCredential.username], firstCredential)
        XCTAssertEqual(credentialStorage.currentUsername, firstCredential.username)

        // Reset for a second round, which should reuse the existing auth credential.
        // Note that as of time of writing, the real RemoteAttestation just hands back whatever
        // auth you gave it in the response, but we don't need to assume that and should be able to
        // handle situations where it gets a fresh auth credential for whatever reason, in which
        // case we should overwrite the credential we have. This tests for that.
        let secondCredential = KBSAuthCredential(credential: .init(username: "abc", password: "456"))
        remoteAttestation.authCredentialInputs = []
        remoteAttestation.promisesToReturn.append(.value(fakeRemoteAttestation(secondCredential)))

        promise = keyBackupService.performRemoteAttestation(auth: nil, enclave: tsConstants.keyBackupEnclave)
        expectation = self.expectation(description: "existingAuth")
        promise.observe {
            expectation.fulfill()
            switch $0 {
            case .success:
                break
            case .failure(let error):
                XCTFail("\(error)")
            }
        }
        wait(for: [expectation], timeout: 10)

        // Should have used existing auth.
        XCTAssertEqual(remoteAttestation.authCredentialInputs, [firstCredential])

        // The new credential should've been stored.
        XCTAssertEqual(credentialStorage.dict[secondCredential.username], secondCredential)
        XCTAssertEqual(credentialStorage.currentUsername, secondCredential.username)

        // Reset for a third round, which should reuse the existing auth credential.
        let thirdCredential = KBSAuthCredential(credential: .init(username: "def", password: "789"))
        remoteAttestation.authCredentialInputs = []
        // Fail one request then accept the next
        remoteAttestation.promisesToReturn.append(.init(error: FakeError()))
        remoteAttestation.promisesToReturn.append(.value(fakeRemoteAttestation(thirdCredential)))

        promise = keyBackupService.performRemoteAttestation(auth: nil, enclave: tsConstants.keyBackupEnclave)
        expectation = self.expectation(description: "failedRequest")
        promise.observe {
            expectation.fulfill()
            switch $0 {
            case .success:
                break
            case .failure(let error):
                XCTFail("\(error)")
            }
        }
        wait(for: [expectation], timeout: 10)

        // Should have used existing auth.
        XCTAssertEqual(remoteAttestation.authCredentialInputs, [secondCredential, nil])

        // The new credential should've been stored.
        XCTAssertEqual(credentialStorage.dict[thirdCredential.username], thirdCredential)
        // The previous credential should've been wiped.
        XCTAssertNil(credentialStorage.dict[secondCredential.username])
        XCTAssertEqual(credentialStorage.currentUsername, thirdCredential.username)
    }

    // MARK: - Helpers

    func AssertPin(
        _ pin: String,
        isValid expectedResult: Bool,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let expectation = XCTestExpectation(description: "Verify Pin")
        keyBackupService.verifyPin(pin) { isValid in
            XCTAssertEqual(isValid, expectedResult, message, file: file, line: line)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func fakeRemoteAttestation(_ credential: KBSAuthCredential) -> RemoteAttestation {
        return RemoteAttestation(
            cookies: [],
            keys: try! .init(
                clientEphemeralKeyPair: Curve25519.generateKeyPair(),
                serverEphemeralPublic: try! Curve25519.generateKeyPair().ecPublicKey().keyData,
                serverStaticPublic: try! Curve25519.generateKeyPair().ecPublicKey().keyData
            ),
            requestId: Data(repeating: 1, count: 10),
            enclaveName: tsConstants.keyBackupEnclave.name,
            auth: .init(username: credential.username, password: credential.credential.password)
        )
    }
}

struct FakeError: Error {}
