//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import Signal
@testable import SignalServiceKit

public class ProvisioningManagerTests {
    private var accountKeyStore: AccountKeyStore!
    private var db: (any DB)!
    private var deviceManager: OWSDeviceManager!
    private var mockDeviceProvisioningService: MockDeviceProvisioningService!
    private var mockIdentityManager: MockIdentityManager!
    private var mockLinkAndSyncManager: MockLinkAndSyncManager!
    private var mockProfileManager: ProvisioningManager.Mocks.ProfileManager!
    private var mockReceiptManager: ProvisioningManager.Mocks.ReceiptManager!
    private var mockTsAccountManager: MockTSAccountManager!

    let recipientDatabaseTable = MockRecipientDatabaseTable()
    let recipientFetcher: RecipientFetcher
    let recipientIdFinder: RecipientIdFinder

    init() {

        self.db = InMemoryDB()
        self.deviceManager = MockDeviceManager()
        self.mockDeviceProvisioningService = MockDeviceProvisioningService()
        self.mockLinkAndSyncManager = MockLinkAndSyncManager()
        self.mockProfileManager = ProvisioningManager.Mocks.ProfileManager()
        self.mockReceiptManager = ProvisioningManager.Mocks.ReceiptManager()
        self.mockTsAccountManager = MockTSAccountManager()

        recipientFetcher = RecipientFetcherImpl(recipientDatabaseTable: recipientDatabaseTable)
        recipientIdFinder = RecipientIdFinder(recipientDatabaseTable: recipientDatabaseTable, recipientFetcher: recipientFetcher)
        mockIdentityManager = MockIdentityManager(recipientIdFinder: recipientIdFinder)
    }

    @Test
    func testProvisioningWithMasterKey() async throws {
        let myAciIdentityKeyPair = IdentityKeyPair.generate()
        let myPniIdentityKeyPair = IdentityKeyPair.generate()
        let myAci = Aci.randomForTesting()
        let myPhoneNumber = E164("+16505550100")!
        let myPni = Pni.randomForTesting()
        let myRecipient = SignalRecipient(aci: myAci, pni: myPni, phoneNumber: myPhoneNumber)
        let profileKey = Aes256Key.generateRandom()
        let accountEntropyPool = AccountEntropyPool()
        let mrbk = BackupKey.generateRandom()
        let readReceiptsEnabled = true
        let provisioningCode = "ABC123"

        let ephemeralDeviceId = "ephemeral-device-id"
        let newDeviceIdentityKeyPair = IdentityKeyPair.generate()

        let accountKeyStore = AccountKeyStore()
        db.write { tx in
            accountKeyStore.setAccountEntropyPool(accountEntropyPool, tx: tx)
            accountKeyStore.setMediaRootBackupKey(mrbk, tx: tx)
            recipientDatabaseTable.insertRecipient(myRecipient, transaction: tx)
            mockIdentityManager.setIdentityKeyPair(myAciIdentityKeyPair.asECKeyPair, for: .aci, tx: tx)
            mockIdentityManager.setIdentityKeyPair(myPniIdentityKeyPair.asECKeyPair, for: .pni, tx: tx)
        }

        mockTsAccountManager.localIdentifiersMock = {
            return LocalIdentifiers(
                aci: myAci,
                pni: myPni,
                e164: myPhoneNumber
            )
        }
        mockProfileManager.localUserProfile = OWSUserProfile(address: .localUser, profileKey: profileKey)
        mockReceiptManager.areReadReceiptsEnabledValue = readReceiptsEnabled
        mockDeviceProvisioningService.deviceProvisioningCodes.append(provisioningCode)

        let provisioningManager = ProvisioningManager(
            accountKeyStore: accountKeyStore,
            db: db,
            deviceManager: deviceManager,
            deviceProvisioningService: mockDeviceProvisioningService,
            identityManager: mockIdentityManager,
            linkAndSyncManager: mockLinkAndSyncManager,
            profileManager: mockProfileManager,
            receiptManager: mockReceiptManager,
            tsAccountManager: mockTsAccountManager
        )

        // New device: Build the linking URL that is shown in the QR code
        let provisioningUrl = DeviceProvisioningURL(
            ephemeralDeviceId: ephemeralDeviceId,
            publicKey: newDeviceIdentityKeyPair.publicKey
        )

        // Old device: Using the provisioning URL read from the new device, build a provisioning
        // message, encrypt id, and send the envelope back to the new device
        _ = try await provisioningManager.provision(with: provisioningUrl, shouldLinkNSync: false)
        let (messageBody, _) = self.mockDeviceProvisioningService.provisionedDevices.removeFirst()
        let provisionEnvelope = try ProvisioningProtoProvisionEnvelope(serializedData: messageBody)

        // New device: take the received provisioning envelope and decrypts the
        // envelope.body using the envelope.publicKey and the new device keypair
        let provisioningCipher = ProvisioningCipher(ourKeyPair: newDeviceIdentityKeyPair)
        let provisionMessageData = try provisioningCipher.decrypt(
            data: provisionEnvelope.body,
            theirPublicKey: PublicKey(provisionEnvelope.publicKey)
        )
        let provisionMessage = try ProvisioningMessage(plaintext: provisionMessageData)

        // Validate that all the data in the decrypted envelope on the new device side matches the
        // values populated by the old device
        switch provisionMessage.rootKey {
        case .accountEntropyPool(let aep):
            #expect(aep.rawData == accountEntropyPool.rawData)
        case .masterKey:
            Issue.record("Expected AEP, but found MasterKey")
        }

        #expect(provisionMessage.aci == myAci)
        #expect(provisionMessage.phoneNumber == myPhoneNumber.stringValue)
        #expect(provisionMessage.pni == myPni)
        #expect(provisionMessage.aciIdentityKeyPair.publicKey == myAciIdentityKeyPair.publicKey)
        #expect(provisionMessage.pniIdentityKeyPair.publicKey == myPniIdentityKeyPair.publicKey)
        #expect(provisionMessage.profileKey == profileKey)
        #expect(provisionMessage.areReadReceiptsEnabled == readReceiptsEnabled)
        #expect(provisionMessage.provisioningCode == provisioningCode)
    }
}

// Mocks

private class MockDeviceProvisioningService: DeviceProvisioningService {
    var deviceProvisioningCodes = [String]()
    func requestDeviceProvisioningCode() async throws -> DeviceProvisioningCodeResponse {
        return .init(verificationCode: deviceProvisioningCodes.removeFirst(), tokenIdentifier: UUID().uuidString)
    }

    var provisionedDevices = [(messageBody: Data, ephemeralDeviceId: String)]()
    func provisionDevice(messageBody: Data, ephemeralDeviceId: String) async throws {
        provisionedDevices.append((messageBody, ephemeralDeviceId))
    }
}

private class MockLinkAndSyncManager: LinkAndSyncManager {

    func isLinkAndSyncEnabledOnPrimary(tx: DBReadTransaction) -> Bool {
        true
    }

    func setIsLinkAndSyncEnabledOnPrimary(_ isEnabled: Bool, tx: DBWriteTransaction) {}

    func generateEphemeralBackupKey() -> BackupKey {
        return .forTesting()
    }

    func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: BackupKey,
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) {
        return
    }

    func waitForBackupAndRestore(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) {
        return
    }
}

private class MockDeviceManager: OWSDeviceManager {
    func setHasReceivedSyncMessage(lastReceivedAt: Date, transaction: DBWriteTransaction) { }

    func hasReceivedSyncMessage(inLastSeconds seconds: UInt, transaction: DBReadTransaction) -> Bool { return true }

    func setMightHaveUnknownLinkedDevice(_ mightHaveUnknownLinkedDevice: Bool, transaction: DBWriteTransaction) { }

    func mightHaveUnknownLinkedDevice(transaction: DBReadTransaction) -> Bool { return true }
}
