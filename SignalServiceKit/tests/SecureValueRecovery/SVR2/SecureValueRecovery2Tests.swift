//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class SecureValueRecovery2Tests: XCTestCase {

    private var db: MockDB!
    private var svr: SecureValueRecovery2Impl!

    private var credentialStorage: SVRAuthCredentialStorageMock!
    private var scheduler: TestScheduler!

    private var mockAccountAttributesUpdater: MockAccountAttributesUpdater!
    private var mock2FAManager: SVR2.TestMocks.OWS2FAManager!
    private var keyValueStoreFactory: InMemoryKeyValueStoreFactory!
    private var localStorage: SVRLocalStorageImpl!
    private var mockConnectionFactory: MockSgxWebsocketConnectionFactory!
    private var mockConnection: MockSgxWebsocketConnection<SVR2WebsocketConfigurator>!
    private var mockTSAccountManager: MockTSAccountManager!
    private var mockTSConstants: TSConstantsMock!

    override func setUp() {
        self.db = MockDB()
        self.credentialStorage = SVRAuthCredentialStorageMock()
        self.scheduler = TestScheduler()
        // Start the scheduler so everything executes synchronously.
        self.scheduler.start()

        mock2FAManager = SVR2.TestMocks.OWS2FAManager()
        keyValueStoreFactory = InMemoryKeyValueStoreFactory()
        localStorage = .init(keyValueStoreFactory: keyValueStoreFactory)

        let mockConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        mockConnection.mockAuth = RemoteAttestation.Auth(username: "username", password: "password")
        self.mockConnection = mockConnection
        mockConnectionFactory = MockSgxWebsocketConnectionFactory()

        mockAccountAttributesUpdater = .init()
        mockTSAccountManager = .init()
        mockTSConstants = TSConstantsMock()

        self.svr = SecureValueRecovery2Impl(
            accountAttributesUpdater: mockAccountAttributesUpdater,
            appReadiness: SVR2.Mocks.AppReadiness(),
            appVersion: MockAppVerion(),
            clientWrapper: MockSVR2ClientWrapper(),
            connectionFactory: mockConnectionFactory,
            credentialStorage: credentialStorage,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: TestSchedulers(scheduler: scheduler),
            storageServiceManager: FakeStorageServiceManager(),
            svrLocalStorage: localStorage,
            syncManager: OWSMockSyncManager(),
            tsAccountManager: mockTSAccountManager,
            tsConstants: mockTSConstants,
            twoFAManager: mock2FAManager
        )
    }

    func testMigration() {
        // Set up the connections to both the old and new enclaves.
        let mockAuth = RemoteAttestation.Auth(username: "username", password: "password")
        let oldEnclave = MrEnclave("0000000000000000000000000000000000000000000000000000000000000000")
        let oldEnclaveConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        oldEnclaveConnection.mockAuth = mockAuth
        let newEnclave = MrEnclave("0101010101010101010101010101010101010101010101010101010101010101")
        let newEnclaveConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        newEnclaveConnection.mockAuth = mockAuth
        mockConnectionFactory.setOnConnectAndPerformHandshake { (config: SVR2WebsocketConfigurator) in
            switch config.mrenclave.stringValue {
            case oldEnclave.stringValue:
                return .value(oldEnclaveConnection)
            case newEnclave.stringValue:
                return .value(newEnclaveConnection)
            default:
                XCTFail("Unexpected enclave connection")
                return .init(error: OWSAssertionError(""))
            }
        }

        let masterKey = Data(repeating: 8, count: Int(SVR.masterKeyLengthBytes))
        let pin = "0000"

        // Set up the local data needed.
        db.write { tx in
            localStorage.setIsMasterKeyBackedUp(true, tx)
            localStorage.setMasterKey(masterKey, tx)
            localStorage.setSVR2MrEnclaveStringValue(oldEnclave.stringValue, tx)
        }
        mockTSAccountManager.registrationStateMock = { .registered }
        mock2FAManager.pinCode = pin

        mockTSConstants.svr2Enclave = newEnclave
        mockTSConstants.svr2PreviousEnclaves = [oldEnclave]

        // Expect backup and expose to the new enclave.
        var newEnclaveRequestCount = 0
        newEnclaveConnection.onSendRequestAndReadResponse = { request in
            defer { newEnclaveRequestCount += 1 }
            var response = SVR2Proto_Response()
            switch newEnclaveRequestCount {
            case 0:
                // First it should issue a backup to the new enclave.
                XCTAssert(request.hasBackup)
                // Test mock encruption just passes along the unmodified master key and pin.
                XCTAssertEqual(request.backup.data, masterKey)
                XCTAssertEqual(request.backup.pin, pin.data(using: .utf8))

                var backupResponse = SVR2Proto_BackupResponse()
                backupResponse.status = .ok
                response.backup = backupResponse
            case 1:
                // Then an expose
                XCTAssert(request.hasExpose)
                // Test mock encruption just passes along the unmodified master key.
                XCTAssertEqual(request.expose.data, masterKey)

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

        // Kick off the migration.
        svr.warmCaches()

        XCTAssertEqual(newEnclaveRequestCount, 2)
        XCTAssertEqual(oldEnclaveRequestCount, 1)

        db.read { tx in
            XCTAssertEqual(localStorage.getSVR2MrEnclaveStringValue(tx), newEnclave.stringValue)
        }

        // If we try to migrate again, it does nothing because we are at the newest enclave.
        svr.warmCaches()
        XCTAssertEqual(newEnclaveRequestCount, 2)
        XCTAssertEqual(oldEnclaveRequestCount, 1)
    }

    func testMigration_forgottenEnclave() {
        // Set up the connections to both the old and new enclaves.
        let mockAuth = RemoteAttestation.Auth(username: "username", password: "password")
        let oldEnclave = MrEnclave("0000000000000000000000000000000000000000000000000000000000000000")
        let oldEnclaveConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        oldEnclaveConnection.mockAuth = mockAuth
        let newEnclave = MrEnclave("0101010101010101010101010101010101010101010101010101010101010101")
        let newEnclaveConnection = MockSgxWebsocketConnection<SVR2WebsocketConfigurator>()
        newEnclaveConnection.mockAuth = mockAuth
        mockConnectionFactory.setOnConnectAndPerformHandshake { (config: SVR2WebsocketConfigurator) in
            switch config.mrenclave.stringValue {
            case newEnclave.stringValue:
                return .value(newEnclaveConnection)
            default:
                XCTFail("Unexpected enclave connection")
                return .init(error: OWSAssertionError(""))
            }
        }

        let masterKey = Data(repeating: 8, count: Int(SVR.masterKeyLengthBytes))
        let pin = "0000"

        // Set up the local data needed.
        db.write { tx in
            localStorage.setIsMasterKeyBackedUp(true, tx)
            localStorage.setMasterKey(masterKey, tx)
            localStorage.setSVR2MrEnclaveStringValue(oldEnclave.stringValue, tx)
        }
        mockTSAccountManager.registrationStateMock = { .registered }
        mock2FAManager.pinCode = pin

        mockTSConstants.svr2Enclave = newEnclave
        // No old enclaves to know about.
        mockTSConstants.svr2PreviousEnclaves = []

        // Expect backup and expose to the new enclave.
        var newEnclaveRequestCount = 0
        newEnclaveConnection.onSendRequestAndReadResponse = { request in
            defer { newEnclaveRequestCount += 1 }
            var response = SVR2Proto_Response()
            switch newEnclaveRequestCount {
            case 0:
                // First it should issue a backup to the new enclave.
                XCTAssert(request.hasBackup)
                // Test mock encruption just passes along the unmodified master key and pin.
                XCTAssertEqual(request.backup.data, masterKey)
                XCTAssertEqual(request.backup.pin, pin.data(using: .utf8))

                var backupResponse = SVR2Proto_BackupResponse()
                backupResponse.status = .ok
                response.backup = backupResponse
            case 1:
                // Then an expose
                XCTAssert(request.hasExpose)
                // Test mock encruption just passes along the unmodified master key.
                XCTAssertEqual(request.expose.data, masterKey)

                var exposeResponse = SVR2Proto_ExposeResponse()
                exposeResponse.status = .ok
                response.expose = exposeResponse
            default:
                XCTFail("Unexpected request!")
                return .init(error: OWSAssertionError(""))
            }
            return .value(response)
        }

        // NOTE: the old enclave should get no requests, its considered dead.

        // Kick off the migration.
        svr.warmCaches()

        XCTAssertEqual(newEnclaveRequestCount, 2)

        db.read { tx in
            XCTAssertEqual(localStorage.getSVR2MrEnclaveStringValue(tx), newEnclave.stringValue)
        }

        // If we try to migrate again, it does nothing because we are at the newest enclave.
        svr.warmCaches()
        XCTAssertEqual(newEnclaveRequestCount, 2)
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

    public func markDisabled(transaction: DBWriteTransaction) {}
}
