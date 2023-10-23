//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

private class MockRecipientMerger: RecipientMerger {
    func applyMergeForLocalAccount(aci: Aci, phoneNumber: E164, pni: Pni?, tx: DBWriteTransaction) -> SignalRecipient {
        fatalError()
    }

    func applyMergeFromStorageService(localIdentifiers: LocalIdentifiers, isPrimaryDevice: Bool, aci: Aci, phoneNumber: E164?, tx: DBWriteTransaction) -> SignalRecipient {
        fatalError()
    }

    func applyMergeFromContactSync(localIdentifiers: LocalIdentifiers, aci: Aci, phoneNumber: E164?, tx: DBWriteTransaction) -> SignalRecipient {
        fatalError()
    }

    func applyMergeFromContactDiscovery(localIdentifiers: LocalIdentifiers, phoneNumber: E164, pni: Pni, aci: Aci?, tx: DBWriteTransaction) -> SignalRecipient? {
        fatalError()
    }

    func applyMergeFromSealedSender(localIdentifiers: LocalIdentifiers, aci: Aci, phoneNumber: E164?, tx: DBWriteTransaction) -> SignalRecipient {
        fatalError()
    }

    var appliedMergesFromPniSignatures = 0
    func applyMergeFromPniSignature(localIdentifiers: LocalIdentifiers, aci: Aci, pni: Pni, tx: DBWriteTransaction) {
        appliedMergesFromPniSignatures += 1
    }
}

final class PniSignatureProcessorTest: XCTestCase {
    private var identityManager: MockIdentityManager!
    private var mockDB: MockDB!
    private var pniSignatureProcessor: PniSignatureProcessor!
    private var recipientMerger: MockRecipientMerger!
    private var recipientStore: MockRecipientDataStore!

    private var aci: Aci!
    private var aciRecipient: SignalRecipient!
    private var aciIdentityKeyPair: IdentityKeyPair!

    private var pni: Pni!
    private var phoneNumber: E164!
    private var pniRecipient: SignalRecipient!
    private var pniIdentityKeyPair: IdentityKeyPair!

    override func setUp() {
        super.setUp()

        recipientStore = MockRecipientDataStore()
        let recipientFetcher = RecipientFetcherImpl(recipientStore: recipientStore)
        let recipientIdFinder = RecipientIdFinder(recipientFetcher: recipientFetcher, recipientStore: recipientStore)
        identityManager = MockIdentityManager(recipientIdFinder: recipientIdFinder)
        mockDB = MockDB()
        recipientMerger = MockRecipientMerger()
        pniSignatureProcessor = PniSignatureProcessorImpl(
            identityManager: identityManager,
            recipientMerger: recipientMerger,
            recipientStore: recipientStore
        )

        aci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        aciRecipient = SignalRecipient(aci: aci, pni: nil, phoneNumber: nil)
        aciIdentityKeyPair = IdentityKeyPair.generate()

        pni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")
        phoneNumber = E164("+16505550101")!
        pniRecipient = SignalRecipient(aci: nil, pni: pni, phoneNumber: phoneNumber)
        pniIdentityKeyPair = IdentityKeyPair.generate()

        mockDB.write { tx in
            recipientStore.insertRecipient(aciRecipient, transaction: tx)
            recipientStore.insertRecipient(pniRecipient, transaction: tx)
        }
        identityManager.recipientIdentities = [
            aciRecipient.uniqueId: OWSRecipientIdentity(
                accountId: aciRecipient.uniqueId,
                identityKey: Data(aciIdentityKeyPair.identityKey.publicKey.keyBytes),
                isFirstKnownKey: true,
                createdAt: Date(),
                verificationState: .default
            ),
            pniRecipient.uniqueId: OWSRecipientIdentity(
                accountId: pniRecipient.uniqueId,
                identityKey: Data(pniIdentityKeyPair.identityKey.publicKey.keyBytes),
                isFirstKnownKey: true,
                createdAt: Date(),
                verificationState: .default
            )
        ]
    }

    private func buildAndHandlePniSignatureMessage(from aci: Aci, pni: Pni, signature: Data) throws {
        let builder = SSKProtoPniSignatureMessage.builder()
        builder.setPni(pni.rawUUID.data)
        builder.setSignature(signature)

        try mockDB.write { tx in
            try pniSignatureProcessor.handlePniSignature(
                builder.buildInfallibly(),
                from: aci,
                localIdentifiers: .forUnitTests,
                tx: tx
            )
        }
    }

    func testValidSignature() throws {
        let signature = Data(pniIdentityKeyPair.signAlternateIdentity(aciIdentityKeyPair.identityKey))
        try buildAndHandlePniSignatureMessage(from: aci, pni: pni, signature: signature)
        XCTAssertEqual(recipientMerger.appliedMergesFromPniSignatures, 1)
    }

    func testWrongPni() {
        let otherPni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b2")
        let signature = Data(pniIdentityKeyPair.signAlternateIdentity(aciIdentityKeyPair.identityKey))
        XCTAssertThrowsError(
            try buildAndHandlePniSignatureMessage(from: aci, pni: otherPni, signature: signature),
            "Shouldn't be able to handle the wrong PNI", { error in
                switch error {
                case PniSignatureProcessorError.missingIdentityKey:
                    break
                default:
                    XCTFail("Threw wrong type of error.")
                }
            }
        )
        XCTAssertEqual(recipientMerger.appliedMergesFromPniSignatures, 0)
    }

    func testMustNotUsePni() {
        let otherAci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a2")
        mockDB.write { tx in
            pniRecipient.aci = otherAci
            recipientStore.updateRecipient(pniRecipient, transaction: tx)
        }
        let signature = Data(pniIdentityKeyPair.signAlternateIdentity(aciIdentityKeyPair.identityKey))
        XCTAssertThrowsError(
            try buildAndHandlePniSignatureMessage(from: aci, pni: pni, signature: signature),
            "Shouldn't be able to handle PNI after its identity key is gone", { error in
                switch error {
                case RecipientIdError.mustNotUsePniBecauseAciExists:
                    break
                default:
                    XCTFail("Threw wrong type of error.")
                }
            }
        )
        XCTAssertEqual(recipientMerger.appliedMergesFromPniSignatures, 0)
    }

    func testInvalidSignature() {
        let signature = Data(IdentityKeyPair.generate().signAlternateIdentity(aciIdentityKeyPair.identityKey))
        XCTAssertThrowsError(
            try buildAndHandlePniSignatureMessage(from: aci, pni: pni, signature: signature),
            "Shouldn't be able to handle an invalid signature", { error in
                switch error {
                case PniSignatureProcessorError.invalidSignature:
                    break
                default:
                    XCTFail("Threw wrong type of error.")
                }
            }
        )
        XCTAssertEqual(recipientMerger.appliedMergesFromPniSignatures, 0)
    }
}
