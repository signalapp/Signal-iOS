//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import LibSignalClient

@testable import Signal
@testable import SignalServiceKit

public class ProvisioningCoordinatorTest: XCTestCase {

    typealias Mocks = ProvisioningCoordinatorImpl.Mocks

    private var provisioningCoordinator: ProvisioningCoordinatorImpl!

    private var identityManagerMock: MockIdentityManager!
    private var messageFactoryMock: Mocks.MessageFactory!
    private var prekeyManagerMock: MockPreKeyManager!
    private var profileManagerMock: Mocks.ProfileManager!
    private var pushRegistrationManagerMock: Mocks.PushRegistrationManager!
    private var receiptManagerMock: Mocks.ReceiptManager!
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var signalServiceMock: OWSSignalServiceMock!
    private var socketManagerMock: SocketManagerMock!
    private var storageServiceManagerMock: FakeStorageServiceManager!
    private var svrMock: SecureValueRecoveryMock!
    private var syncManagerMock: Mocks.SyncManager!
    private var threadStoreMock: MockThreadStore!
    private var tsAccountManagerMock: MockTSAccountManager!
    private var udManagerMock: Mocks.UDManager!

    public override func setUp() async throws {

        let mockDb = MockDB()

        let recipientDbTable = MockRecipientDatabaseTable()
        let recipientFetcher = RecipientFetcherImpl(recipientDatabaseTable: recipientDbTable)
        let recipientIdFinder = RecipientIdFinder(
            recipientDatabaseTable: recipientDbTable,
            recipientFetcher: recipientFetcher
        )
        self.identityManagerMock = .init(recipientIdFinder: recipientIdFinder)

        self.messageFactoryMock = .init()
        self.prekeyManagerMock = .init()
        self.profileManagerMock = .init()
        self.pushRegistrationManagerMock = .init()
        self.receiptManagerMock = .init()
        self.registrationStateChangeManagerMock = .init()
        self.signalServiceMock = .init()
        self.socketManagerMock = .init()
        self.storageServiceManagerMock = .init()
        self.svrMock = .init()
        self.syncManagerMock = .init()
        self.threadStoreMock = .init()
        self.tsAccountManagerMock = .init()
        self.udManagerMock = .init()

        self.provisioningCoordinator = ProvisioningCoordinatorImpl(
            db: mockDb,
            identityManager: identityManagerMock,
            messageFactory: messageFactoryMock,
            preKeyManager: prekeyManagerMock,
            profileManager: profileManagerMock,
            pushRegistrationManager: pushRegistrationManagerMock,
            receiptManager: receiptManagerMock,
            registrationStateChangeManager: registrationStateChangeManagerMock,
            signalService: signalServiceMock,
            socketManager: socketManagerMock,
            storageServiceManager: storageServiceManagerMock,
            svr: svrMock,
            syncManager: syncManagerMock,
            threadStore: threadStoreMock,
            tsAccountManager: tsAccountManagerMock,
            udManager: udManagerMock
        )

        tsAccountManagerMock.registrationStateMock = { .unregistered }
    }

    public func testProvisioning() async throws {
        let provisioningMessage = ProvisionMessage(
            aci: .randomForTesting(),
            phoneNumber: "+17875550100",
            pni: .randomForTesting(),
            aciIdentityKeyPair: try keyPairForTesting(),
            pniIdentityKeyPair: try keyPairForTesting(),
            profileKey: .generateRandom(),
            masterKey: Cryptography.generateRandomBytes(SVR.masterKeyLengthBytes),
            areReadReceiptsEnabled: true,
            primaryUserAgent: nil,
            provisioningCode: "1234",
            provisioningVersion: 1
        )
        let deviceName = "test device"
        let deviceId = UInt32.random(in: 1...5)

        let mockSession = UrlSessionMock()

        let verificationResponse = ProvisioningServiceResponses.VerifySecondaryDeviceResponse(
            pni: provisioningMessage.pni!,
            deviceId: deviceId
        )

        mockSession.responder = { request in
            if request.url!.absoluteString.hasSuffix("v1/devices/link") {
                return try! JSONEncoder().encode(verificationResponse)
            } else if request.url!.absoluteString.hasSuffix("v1/devices/capabilities") {
                return Data()
            } else {
                XCTFail("Unexpected request!")
                return Data()
            }
        }

        signalServiceMock.mockUrlSessionBuilder = { (signalServiceInfo, _, _) in
            XCTAssertEqual(
                signalServiceInfo.baseUrl,
                SignalServiceType.mainSignalServiceIdentified.signalServiceInfo().baseUrl
            )
            return mockSession
        }

        pushRegistrationManagerMock.mockRegistrationId = .init(apnsToken: "apn", voipToken: nil)

        var didSetLocalIdentifiers = false
        registrationStateChangeManagerMock.didProvisionSecondaryMock = { e164, aci, pni, _, storedDeviceId in
            XCTAssertEqual(e164.stringValue, provisioningMessage.phoneNumber)
            XCTAssertEqual(aci, provisioningMessage.aci)
            XCTAssertEqual(pni, provisioningMessage.pni)
            XCTAssertEqual(storedDeviceId, deviceId)
            didSetLocalIdentifiers = true
        }

        let provisioningResult = await provisioningCoordinator.completeProvisioning(
            provisionMessage: provisioningMessage,
            deviceName: deviceName
        )

        XCTAssert(didSetLocalIdentifiers)
        XCTAssert(prekeyManagerMock.didFinalizeRegistrationPrekeys)
        XCTAssertEqual(profileManagerMock.localProfileKeyMock, provisioningMessage.profileKey)
        XCTAssertEqual(identityManagerMock.identityKeyPairs[.aci], provisioningMessage.aciIdentityKeyPair)
        XCTAssertEqual(identityManagerMock.identityKeyPairs[.pni], provisioningMessage.pniIdentityKeyPair)
        XCTAssertEqual(svrMock.syncedMasterKey, provisioningMessage.masterKey)

        switch provisioningResult {
        case .success:
            break
        default:
            XCTFail("Got failure result!")
        }
    }

    public func testProvisioning_noMasterKey() async throws {
        let provisioningMessage = ProvisionMessage(
            aci: .randomForTesting(),
            phoneNumber: "+17875550100",
            pni: .randomForTesting(),
            aciIdentityKeyPair: try keyPairForTesting(),
            pniIdentityKeyPair: try keyPairForTesting(),
            profileKey: .generateRandom(),
            masterKey: nil,
            areReadReceiptsEnabled: true,
            primaryUserAgent: nil,
            provisioningCode: "1234",
            provisioningVersion: 1
        )
        let deviceName = "test device"
        let deviceId = UInt32.random(in: 1...5)

        let mockSession = UrlSessionMock()

        let verificationResponse = ProvisioningServiceResponses.VerifySecondaryDeviceResponse(
            pni: provisioningMessage.pni!,
            deviceId: deviceId
        )

        mockSession.responder = { request in
            if request.url!.absoluteString.hasSuffix("v1/devices/link") {
                return try! JSONEncoder().encode(verificationResponse)
            } else if request.url!.absoluteString.hasSuffix("v1/devices/capabilities") {
                return Data()
            } else {
                XCTFail("Unexpected request!")
                return Data()
            }
        }

        signalServiceMock.mockUrlSessionBuilder = { (signalServiceInfo, _, _) in
            XCTAssertEqual(
                signalServiceInfo.baseUrl,
                SignalServiceType.mainSignalServiceIdentified.signalServiceInfo().baseUrl
            )
            return mockSession
        }

        pushRegistrationManagerMock.mockRegistrationId = .init(apnsToken: "apn", voipToken: nil)

        var didSetLocalIdentifiers = false
        registrationStateChangeManagerMock.didProvisionSecondaryMock = { e164, aci, pni, _, storedDeviceId in
            XCTAssertEqual(e164.stringValue, provisioningMessage.phoneNumber)
            XCTAssertEqual(aci, provisioningMessage.aci)
            XCTAssertEqual(pni, provisioningMessage.pni)
            XCTAssertEqual(storedDeviceId, deviceId)
            didSetLocalIdentifiers = true
        }

        // We will send a master key sync message.
        syncManagerMock.sendKeysSyncMessageMock = {
            NotificationCenter.default.post(name: .OWSSyncManagerKeysSyncDidComplete, object: nil)
        }

        let provisioningResult = await provisioningCoordinator.completeProvisioning(
            provisionMessage: provisioningMessage,
            deviceName: deviceName
        )

        XCTAssert(didSetLocalIdentifiers)
        XCTAssert(prekeyManagerMock.didFinalizeRegistrationPrekeys)
        XCTAssertEqual(profileManagerMock.localProfileKeyMock, provisioningMessage.profileKey)
        XCTAssertEqual(identityManagerMock.identityKeyPairs[.aci], provisioningMessage.aciIdentityKeyPair)
        XCTAssertEqual(identityManagerMock.identityKeyPairs[.pni], provisioningMessage.pniIdentityKeyPair)
        XCTAssertEqual(svrMock.syncedMasterKey, provisioningMessage.masterKey)

        switch provisioningResult {
        case .success:
            break
        default:
            XCTFail("Got failure result!")
        }
    }

    private func keyPairForTesting() throws -> ECKeyPair {
        let privateKey = try PrivateKey(Array(repeating: 0, count: 31) + [.random(in: 0..<0x48)])
        return ECKeyPair(IdentityKeyPair(publicKey: privateKey.publicKey, privateKey: privateKey))
    }
}

extension ProvisioningCoordinatorTest {

    class UrlSessionMock: BaseOWSURLSessionMock {

        var responder: ((TSRequest) -> Data)?

        override func promiseForTSRequest(_ rawRequest: TSRequest) -> Promise<HTTPResponse> {
            let responseBody = responder!(rawRequest)
            return .value(HTTPResponseImpl(
                requestUrl: rawRequest.url!,
                status: 200,
                headers: OWSHttpHeaders(),
                bodyData: responseBody
            ))
        }
    }

    class MockIdentityManager: SignalServiceKit.MockIdentityManager {

        var identityKeyPairs = [OWSIdentity: ECKeyPair]()

        override func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) {
            identityKeyPairs[identity] = keyPair
        }
    }
}
