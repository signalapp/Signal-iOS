//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
@testable import SignalServiceKit

struct DonationReceiptCredentialRedemptionJobFinderTest {
    let db = InMemoryDB()
    let jobFinder = DonationReceiptCredentialRedemptionJobFinder()

    @Test
    func testJobFinder() {
        let subscriberID: Data = Randomness.generateRandomBytes(32)

        db.write { tx in
            #expect(!jobFinder.subscriptionJobExists(
                subscriberID: subscriberID,
                tx: tx,
            ))

            let (
                receiptCredentialRequestContext,
                receiptCredentialRequest,
            ) = ReceiptCredentialManager.generateReceiptRequest()

            try! DonationReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "STRIPE",
                paymentMethod: "sepa",
                receiptCredentialRequestContext: receiptCredentialRequestContext.serialize(),
                receiptCredentialRequest: receiptCredentialRequest.serialize(),
                subscriberID: subscriberID,
                targetSubscriptionLevel: 123,
                priorSubscriptionLevel: 0,
                isNewSubscription: false,
                isBoost: false,
                amount: nil,
                currencyCode: nil,
                boostPaymentIntentID: "",
            ).insert(tx.database)

            #expect(jobFinder.subscriptionJobExists(
                subscriberID: subscriberID,
                tx: tx,
            ))
        }
    }
}
