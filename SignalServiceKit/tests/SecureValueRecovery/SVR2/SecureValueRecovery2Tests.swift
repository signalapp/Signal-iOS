//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
import XCTest

@testable public import SignalServiceKit

class SecureValueRecovery2Tests: XCTestCase {

    private var db: InMemoryDB!
    private var svr: SecureValueRecovery2Impl!

    private var credentialManager: SVRAuthCredentialManager!

    private var mock2FAManager: SVR2.TestMocks.OWS2FAManager!
    private var accountKeyStore: AccountKeyStore!
    private var localStorage: SVRLocalStorage!
    private var mockConnectionFactory: MockSgxWebsocketConnectionFactory!
    private var mockConnection: MockSgxWebsocketConnection<SVR2WebsocketConfigurator>!
    private var mockTSConstants: TSConstantsMock!

    override func setUp() {
        self.db = InMemoryDB()
        self.credentialManager = SVRAuthCredentialManager.mock()

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
            credentialManager: credentialManager,
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
}

// MARK: -

struct SVRUtilTest {

    @Test(arguments: [
        ("1234", "1234"),
        (" LukeIAmYourFather123\n", "LukeIAmYourFather123"),
    ])
    func testNormalizePin(testCase: (pin: String, normalizedPin: String)) {
        #expect(SVRUtil.normalizePin(testCase.pin) == testCase.normalizedPin)
    }

    @Test(arguments: [
        ("1234", "$argon2i$v=19$m=512,t=64,p=1$CxIHZ5tsrelHqqMfW7AsZw$4v19z1zecfP1hZ4b8RG1RFv6XDgU3BAEXME01r+xIBA"),
        (" LukeIAmYourFather123\n", "$argon2i$v=19$m=512,t=64,p=1$CxIHZ5tsrelHqqMfW7AsZw$OgeedfJVzRTOUJ9CqeJ0e5ENGwfYiGyGj7/ejVrLOnw"),
    ])
    func testPinHashing(testCase: (pin: String, oldEncodedString: String)) throws {
        let encodedString = try SVRUtil.deriveEncodedPINVerificationString(pin: testCase.pin)
        #expect(SVRUtil.verifyPIN(pin: testCase.pin, againstEncodedPINVerificationString: encodedString))
        // Some other password should fail to verify.
        #expect(!SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: encodedString))

        // Test that pin hashes generated by argon2 are compatible with our current
        // verification strategy; we store these hashes to disk for verification,
        // so future verification needs to be backwards compatible.
        // Note that we don't need _new_ verification strings to be equivalent to old ones,
        // as long as both pass verification.
        #expect(SVRUtil.verifyPIN(pin: testCase.pin, againstEncodedPINVerificationString: testCase.oldEncodedString))
        // Some other password should fail to verify.
        #expect(!SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: testCase.oldEncodedString))
    }
}

// MARK: -

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
