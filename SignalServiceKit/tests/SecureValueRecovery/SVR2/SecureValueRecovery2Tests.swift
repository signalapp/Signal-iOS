//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable public import SignalServiceKit

class SecureValueRecovery2Tests: XCTestCase {

    private var db: InMemoryDB!
    private var svr: SecureValueRecovery2Impl!

    private var credentialStorage: SVRAuthCredentialStorageMock!

    private var mock2FAManager: SVR2.TestMocks.OWS2FAManager!
    private var accountKeyStore: AccountKeyStore!
    private var localStorage: SVRLocalStorage!
    private var mockConnectionFactory: MockSgxWebsocketConnectionFactory!
    private var mockConnection: MockSgxWebsocketConnection<SVR2WebsocketConfigurator>!
    private var mockTSConstants: TSConstantsMock!

    override func setUp() {
        self.db = InMemoryDB()
        self.credentialStorage = SVRAuthCredentialStorageMock()

        mock2FAManager = SVR2.TestMocks.OWS2FAManager()
        accountKeyStore = AccountKeyStore(
            backupSettingsStore: BackupSettingsStore(),
        )
        localStorage = SVRLocalStorage()

        let mockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        mockConnection.mockAuth = RemoteAttestationAuth(username: "username", password: "password")
        self.mockConnection = mockConnection
        mockConnectionFactory = MockSgxWebsocketConnectionFactory()

        mockTSConstants = TSConstantsMock()

        self.svr = SecureValueRecovery2Impl(
            connectionFactory: mockConnectionFactory,
            credentialStorage: credentialStorage,
            db: db,
            accountKeyStore: accountKeyStore,
            pinHasher: MockPinHasher(),
            remoteAttestationAuthFetcher: RemoteAttestationAuthFetcher(networkManager: MockNetworkManager()),
            storageServiceManager: FakeStorageServiceManager(),
            svrLocalStorage: localStorage,
            tsConstants: mockTSConstants,
            twoFAManager: mock2FAManager,
        )
    }

    @MainActor
    func testMigration() async throws {
        // Set up the connections to both the old and new enclaves.
        let mockAuth = RemoteAttestationAuth(username: "username", password: "password")

        let oldEnclave = MrEnclave("0000000000000000000000000000000000000000000000000000000000000000")
        let oldEnclaveConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        oldEnclaveConnection.mockEnclave = oldEnclave
        oldEnclaveConnection.mockAuth = mockAuth

        let newEnclave = MrEnclave("0101010101010101010101010101010101010101010101010101010101010101")
        let newEnclaveConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        newEnclaveConnection.mockEnclave = newEnclave
        newEnclaveConnection.mockAuth = mockAuth

        mockConnectionFactory.setOnConnectAndPerformHandshake { (config: SVR2WebsocketConfigurator) in
            switch config.mrenclave.stringValue {
            case oldEnclave.stringValue:
                return oldEnclaveConnection
            case newEnclave.stringValue:
                return newEnclaveConnection
            default:
                XCTFail("Unexpected enclave connection")
                throw OWSAssertionError("")
            }
        }

        let aep = AccountEntropyPool()
        let pin = "0000"

        // Set up the local data needed.
        db.write { tx in
            accountKeyStore.setAccountEntropyPool(aep, tx: tx)
        }
        mock2FAManager.pinCode = pin

        // Expect backup and expose to the new enclave.
        var newEnclaveRequestCount = 0
        newEnclaveConnection.onSendRequestAndReadResponse = { request in
            defer { newEnclaveRequestCount += 1 }
            var response = SVR2Proto_Response()
            switch newEnclaveRequestCount {
            case 0:
                // First it should issue a backup to the new enclave.
                XCTAssert(request.hasBackup)
                XCTAssertEqual(request.backup.data.count, 48)
                XCTAssertEqual(request.backup.pin.count, 32)

                var backupResponse = SVR2Proto_BackupResponse()
                backupResponse.status = .ok
                response.backup = backupResponse
            case 1:
                // Then an expose
                XCTAssert(request.hasExpose)
                XCTAssertEqual(request.expose.data.count, 48)

                var exposeResponse = SVR2Proto_ExposeResponse()
                exposeResponse.status = .ok
                response.expose = exposeResponse
            default:
                XCTFail("Unexpected request!")
                return .init(error: OWSAssertionError(""))
            }
            return .value(response)
        }

        // The old enclave should just get a delete.
        var oldEnclaveRequestCount = 0
        oldEnclaveConnection.onSendRequestAndReadResponse = { request in
            defer { oldEnclaveRequestCount += 1 }
            var response = SVR2Proto_Response()
            switch oldEnclaveRequestCount {
            case 0:
                // First it should issue a backup to the old enclave
                XCTAssert(request.hasBackup)
                XCTAssertEqual(request.backup.data.count, 48)
                XCTAssertEqual(request.backup.pin.count, 32)

                var backupResponse = SVR2Proto_BackupResponse()
                backupResponse.status = .ok
                response.backup = backupResponse
            case 1:
                // Then an expose
                XCTAssert(request.hasExpose)
                XCTAssertEqual(request.expose.data.count, 48)

                var exposeResponse = SVR2Proto_ExposeResponse()
                exposeResponse.status = .ok
                response.expose = exposeResponse
            case 2:
                // Then a delete
                XCTAssert(request.hasDelete)
                // New enclave should be all backed up by now.
                XCTAssertEqual(newEnclaveRequestCount, 2)

                response.delete = SVR2Proto_DeleteResponse()
            default:
                XCTFail("Unexpected request")
                return .init(error: OWSAssertionError(""))
            }
            return .value(response)
        }

        // Migrate to the old enclave.
        mockTSConstants.svr2Enclaves = [oldEnclave]
        _ = try await svr.refreshBackupIfNecessary()
        XCTAssertEqual(newEnclaveRequestCount, 0)
        XCTAssertEqual(oldEnclaveRequestCount, 2)
        db.read { tx in
            XCTAssertEqual(localStorage.completedBackupStore.allKeys(transaction: tx), [oldEnclave.stringValue])
        }

        // Migrate to the new enclave.
        mockTSConstants.svr2Enclaves = [newEnclave, oldEnclave]
        _ = try await svr.refreshBackupIfNecessary()
        XCTAssertEqual(newEnclaveRequestCount, 2)
        XCTAssertEqual(oldEnclaveRequestCount, 3)
        db.read { tx in
            XCTAssertEqual(localStorage.completedBackupStore.allKeys(transaction: tx), [newEnclave.stringValue])
        }

        // Migrate again; nothing should change.
        _ = try await svr.refreshBackupIfNecessary()
        XCTAssertEqual(newEnclaveRequestCount, 2)
        XCTAssertEqual(oldEnclaveRequestCount, 3)
        db.read { tx in
            XCTAssertEqual(localStorage.completedBackupStore.allKeys(transaction: tx), [newEnclave.stringValue])
        }
    }

    @MainActor
    func testMigration_forgottenEnclave() async throws {
        // Set up the connections to both the old and new enclaves.
        let mockAuth = RemoteAttestationAuth(username: "username", password: "password")

        let oldEnclave = MrEnclave("0000000000000000000000000000000000000000000000000000000000000000")
        let oldEnclaveConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        oldEnclaveConnection.mockEnclave = oldEnclave
        oldEnclaveConnection.mockAuth = mockAuth

        let newEnclave = MrEnclave("0101010101010101010101010101010101010101010101010101010101010101")
        let newEnclaveConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        newEnclaveConnection.mockEnclave = newEnclave
        newEnclaveConnection.mockAuth = mockAuth

        mockConnectionFactory.setOnConnectAndPerformHandshake { (config: SVR2WebsocketConfigurator) in
            switch config.mrenclave.stringValue {
            case oldEnclave.stringValue:
                return oldEnclaveConnection
            case newEnclave.stringValue:
                return newEnclaveConnection
            default:
                XCTFail("Unexpected enclave connection")
                throw OWSAssertionError("")
            }
        }

        let aep = AccountEntropyPool()
        let pin = "0000"

        // Set up the local data needed.
        db.write { tx in
            accountKeyStore.setAccountEntropyPool(aep, tx: tx)
        }
        mock2FAManager.pinCode = pin

        // Expect backup and expose to the new enclave.
        var newEnclaveRequestCount = 0
        newEnclaveConnection.onSendRequestAndReadResponse = { request in
            defer { newEnclaveRequestCount += 1 }
            var response = SVR2Proto_Response()
            switch newEnclaveRequestCount {
            case 0:
                // First it should issue a backup to the new enclave.
                XCTAssert(request.hasBackup)
                XCTAssertEqual(request.backup.data.count, 48)
                XCTAssertEqual(request.backup.pin.count, 32)

                var backupResponse = SVR2Proto_BackupResponse()
                backupResponse.status = .ok
                response.backup = backupResponse
            case 1:
                // Then an expose
                XCTAssert(request.hasExpose)
                XCTAssertEqual(request.expose.data.count, 48)

                var exposeResponse = SVR2Proto_ExposeResponse()
                exposeResponse.status = .ok
                response.expose = exposeResponse
            default:
                XCTFail("Unexpected request!")
                return .init(error: OWSAssertionError(""))
            }
            return .value(response)
        }

        // The old enclave should just get a delete.
        var oldEnclaveRequestCount = 0
        oldEnclaveConnection.onSendRequestAndReadResponse = { request in
            defer { oldEnclaveRequestCount += 1 }
            var response = SVR2Proto_Response()
            switch oldEnclaveRequestCount {
            case 0:
                // First it should issue a backup to the old enclave
                XCTAssert(request.hasBackup)
                XCTAssertEqual(request.backup.data.count, 48)
                XCTAssertEqual(request.backup.pin.count, 32)

                var backupResponse = SVR2Proto_BackupResponse()
                backupResponse.status = .ok
                response.backup = backupResponse
            case 1:
                // Then an expose
                XCTAssert(request.hasExpose)
                XCTAssertEqual(request.expose.data.count, 48)

                var exposeResponse = SVR2Proto_ExposeResponse()
                exposeResponse.status = .ok
                response.expose = exposeResponse
            default:
                XCTFail("Unexpected request")
                return .init(error: OWSAssertionError(""))
            }
            return .value(response)
        }

        // Migrate to the old enclave.
        mockTSConstants.svr2Enclaves = [oldEnclave]
        _ = try await svr.refreshBackupIfNecessary()
        XCTAssertEqual(newEnclaveRequestCount, 0)
        XCTAssertEqual(oldEnclaveRequestCount, 2)
        db.read { tx in
            XCTAssertEqual(localStorage.completedBackupStore.allKeys(transaction: tx), [oldEnclave.stringValue])
        }

        // Migrate to the new enclave.
        mockTSConstants.svr2Enclaves = [newEnclave]
        _ = try await svr.refreshBackupIfNecessary()
        XCTAssertEqual(newEnclaveRequestCount, 2)
        XCTAssertEqual(oldEnclaveRequestCount, 2)
        db.read { tx in
            XCTAssertEqual(localStorage.completedBackupStore.allKeys(transaction: tx), [newEnclave.stringValue])
        }
    }

    func testPinHashingNumeric() throws {
        let pin = "1234"
        let normalizedPin = SVRUtil.normalizePin(pin)
        XCTAssertEqual(pin, normalizedPin)

        let encodedString = try SVRUtil.deriveEncodedPINVerificationString(pin: pin)
        XCTAssert(SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: encodedString))
        // Some other password should fail to verify.
        XCTAssertFalse(SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: encodedString))

        // Test that pin hashes generated by argon2 are compatible with our current
        // verification strategy; we store these hashes to disk for verification,
        // so future verification needs to be backwards compatible.
        // Note that we don't need _new_ verification strings to be equivalent to old ones,
        // as long as both pass verification.
        let argon2EncodedString = "$argon2i$v=19$m=512,t=64,p=1$CxIHZ5tsrelHqqMfW7AsZw$4v19z1zecfP1hZ4b8RG1RFv6XDgU3BAEXME01r+xIBA"
        // This string was generated using:
        // let (_, encodedString) = try Argon2.hash(
        //    iterations: 64,
        //    memoryInKiB: 512,
        //    threads: 1,
        //    password: normalizedPin.data(using: .utf8)!,
        //    // Generated using `Cryptography.generateRandomBytes(SVRUtil.Constants.pinSaltLengthBytes)`
        //    salt: Data([11, 18, 7, 103, 155, 108, 173, 233, 71, 170, 163, 31, 91, 176, 44, 103]),
        //    desiredLength: 32,
        //    variant: .i,
        //    version: .v13
        // )

        XCTAssert(SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: argon2EncodedString))
        // Some other password should fail to verify.
        XCTAssertFalse(SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: argon2EncodedString))
    }

    func testPinHashingAlphaNumeric() throws {
        let pin = " LukeIAmYourFather123\n"
        let normalizedPin = SVRUtil.normalizePin(pin)
        XCTAssertEqual("LukeIAmYourFather123", normalizedPin)

        let encodedString = try SVRUtil.deriveEncodedPINVerificationString(pin: pin)
        XCTAssert(SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: encodedString))
        // Some other password should fail to verify.
        XCTAssertFalse(SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: encodedString))

        // Test that pin hashes generated by argon2 are compatible with our current
        // verification strategy; we store these hashes to disk for verification,
        // so future verification needs to be backwards compatible.
        // Note that we don't need _new_ verification strings to be equivalent to old ones,
        // as long as both pass verification.
        let argon2EncodedString = "$argon2i$v=19$m=512,t=64,p=1$CxIHZ5tsrelHqqMfW7AsZw$OgeedfJVzRTOUJ9CqeJ0e5ENGwfYiGyGj7/ejVrLOnw"
        // This string was generated using:
        // let (_, encodedString) = try Argon2.hash(
        //    iterations: 64,
        //    memoryInKiB: 512,
        //    threads: 1,
        //    password: normalizedPin.data(using: .utf8)!,
        //    // Generated using `Cryptography.generateRandomBytes(SVRUtil.Constants.pinSaltLengthBytes)`
        //    salt: Data([11, 18, 7, 103, 155, 108, 173, 233, 71, 170, 163, 31, 91, 176, 44, 103]),
        //    desiredLength: 32,
        //    variant: .i,
        //    version: .v13
        // )

        XCTAssert(SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: argon2EncodedString))
        // Some other password should fail to verify.
        XCTAssertFalse(SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: argon2EncodedString))
    }
}

extension SVR2 {
    public enum TestMocks {
        public typealias OWS2FAManager = _SVR2_OWS2FAManagerTestMock
    }
}

// MARK: - OWS2FAManager

public class _SVR2_OWS2FAManagerTestMock: SVR2.Shims.OWS2FAManager {
    public init() {}

    public var pinCode: String!

    public func pinCode(transaction: DBReadTransaction) -> String? {
        return pinCode
    }
}
