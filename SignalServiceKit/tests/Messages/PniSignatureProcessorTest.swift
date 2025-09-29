//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final private class MockRecipientMerger: RecipientMerger {
    func applyMergeForLocalAccount(aci: Aci, phoneNumber: E164, pni: Pni?, tx: DBWriteTransaction) -> SignalRecipient {
        fatalError()
    }

    func applyMergeFromStorageService(localIdentifiers: LocalIdentifiers, isPrimaryDevice: Bool, serviceIds: AtLeastOneServiceId, phoneNumber: E164?, tx: DBWriteTransaction) -> SignalRecipient {
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

    func splitUnregisteredRecipientIfNeeded(localIdentifiers: LocalIdentifiers, unregisteredRecipient: SignalRecipient, tx: DBWriteTransaction) {
        fatalError()
    }
}

final class PniSignatureProcessorTest: XCTestCase {
    private var identityManager: MockIdentityManager!
    private var mockDB: InMemoryDB!
    private var pniSignatureProcessor: PniSignatureProcessor!
    private var recipientMerger: MockRecipientMerger!
    private var recipientDatabaseTable: RecipientDatabaseTable!

    private var aci: Aci!
    private var aciRecipient: SignalRecipient!
    private var aciIdentityKeyPair: IdentityKeyPair!

    private var pni: Pni!
    private var phoneNumber: E164!
    private var pniRecipient: SignalRecipient!
    private var pniIdentityKeyPair: IdentityKeyPair!

    override func setUp() {
        super.setUp()

        recipientDatabaseTable = RecipientDatabaseTable()
        let recipientFetcher = RecipientFetcherImpl(
            recipientDatabaseTable: recipientDatabaseTable,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        let recipientIdFinder = RecipientIdFinder(recipientDatabaseTable: recipientDatabaseTable, recipientFetcher: recipientFetcher)
        identityManager = MockIdentityManager(recipientIdFinder: recipientIdFinder)
        mockDB = InMemoryDB()
        recipientMerger = MockRecipientMerger()
        pniSignatureProcessor = PniSignatureProcessorImpl(
            identityManager: identityManager,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientMerger: recipientMerger
        )

        aci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        aciRecipient = SignalRecipient(aci: aci, pni: nil, phoneNumber: nil)
        aciIdentityKeyPair = IdentityKeyPair.generate()

        pni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")
        phoneNumber = E164("+16505550101")!
        pniRecipient = SignalRecipient(aci: nil, pni: pni, phoneNumber: phoneNumber)
        pniIdentityKeyPair = IdentityKeyPair.generate()

        mockDB.write { tx in
            recipientDatabaseTable.insertRecipient(aciRecipient, transaction: tx)
            recipientDatabaseTable.insertRecipient(pniRecipient, transaction: tx)
        }
        identityManager.recipientIdentities = [
            aciRecipient.uniqueId: OWSRecipientIdentity(
                uniqueId: aciRecipient.uniqueId,
                identityKey: aciIdentityKeyPair.identityKey.publicKey.keyBytes,
                isFirstKnownKey: true,
                createdAt: Date(),
                verificationState: .default
            ),
            pniRecipient.uniqueId: OWSRecipientIdentity(
                uniqueId: pniRecipient.uniqueId,
                identityKey: pniIdentityKeyPair.identityKey.publicKey.keyBytes,
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
        let signature = pniIdentityKeyPair.signAlternateIdentity(aciIdentityKeyPair.identityKey)
        try buildAndHandlePniSignatureMessage(from: aci, pni: pni, signature: signature)
        XCTAssertEqual(recipientMerger.appliedMergesFromPniSignatures, 1)
    }

    func testWrongPni() {
        let otherPni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b2")
        let signature = pniIdentityKeyPair.signAlternateIdentity(aciIdentityKeyPair.identityKey)
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
            recipientDatabaseTable.updateRecipient(pniRecipient, transaction: tx)
        }
        let signature = pniIdentityKeyPair.signAlternateIdentity(aciIdentityKeyPair.identityKey)
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
        let signature = IdentityKeyPair.generate().signAlternateIdentity(aciIdentityKeyPair.identityKey)
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
