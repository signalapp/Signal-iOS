//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class JobRecordTest: XCTestCase {
    private let inMemoryDB = InMemoryDB()

    private func jobRecordClass(
        forRecordType recordType: JobRecord.JobRecordType
    ) -> any (JobRecord & ValidatableModel).Type {
        switch recordType {
        case .incomingContactSync: return IncomingContactSyncJobRecord.self
        case .legacyMessageDecrypt: return LegacyMessageDecryptJobRecord.self
        case .localUserLeaveGroup: return LocalUserLeaveGroupJobRecord.self
        case .messageSender: return MessageSenderJobRecord.self
        case .donationReceiptCredentialRedemption: return DonationReceiptCredentialRedemptionJobRecord.self
        case .sendGiftBadge: return SendGiftBadgeJobRecord.self
        case .sessionReset: return SessionResetJobRecord.self
        case .callRecordDeleteAll: return CallRecordDeleteAllJobRecord.self
        case .bulkDeleteInteractionJobRecord: return BulkDeleteInteractionJobRecord.self
        case .backupReceiptsCredentialRedemption: return BackupReceiptCredentialRedemptionJobRecord.self
        }
    }

    // MARK: - Round trip

    func testRoundTrip() {
        func roundTripValidateConstant<T: JobRecord & ValidatableModel>(constant: T, index: Int) {
            inMemoryDB.insert(record: constant)

            let deserialized: T? = inMemoryDB.fetchExactlyOne(modelType: T.self)

            guard let deserialized else {
                XCTFail("Failed to fetch constant \(index) for class \(T.self)!")
                return
            }

            do {
                try deserialized.validate(against: constant)
                try deserialized.commonValidate(against: constant)
            } catch ValidatableModelError.failedToValidate {
                XCTFail("Failed to validate constant \(index) for class \(T.self)!")
            } catch {
                XCTFail("Unexpected error while validating constant \(index) for class \(T.self)!")
            }

            inMemoryDB.remove(model: deserialized)
        }

        for jobRecordType in JobRecord.JobRecordType.allCases {
            let jobRecordClass = jobRecordClass(forRecordType: jobRecordType)

            for (idx, (constant, _)) in jobRecordClass.constants.enumerated() {
                roundTripValidateConstant(constant: constant, index: idx)
            }
        }
    }

    // MARK: - Hardcoded constant data

    enum HardcodedDataTestMode {
        case runTest
        case printStrings

        /// Toggle this to use ``testHardcodedJsonDataDecodes()`` to print
        /// hardcoded strings, for example when adding new constants.
        static let mode: Self = .runTest
    }

    func testHardcodedJsonDataDecodes() {
        func validateConstantAgainstJsonData<T: JobRecord & ValidatableModel>(
            constant: T,
            jsonData: Data,
            index: Int
        ) {
            do {
                let decoded = try JSONDecoder().decode(T.self, from: jsonData)
                try constant.validate(against: decoded)
                try constant.commonValidate(against: decoded)
            } catch let error where error is DecodingError {
                XCTFail("Failed to decode JSON model for constant \(index) of class \(T.self): \(error)")
            } catch ValidatableModelError.failedToValidate {
                XCTFail("Failed to validate JSON-decoded model for constant \(index) of class \(T.self)")
            } catch {
                XCTFail("Unexpected error for constant \(index) of class \(T.self)")
            }
        }

        for jobRecordType in JobRecord.JobRecordType.allCases {
            let jobRecordClass = jobRecordClass(forRecordType: jobRecordType)

            switch HardcodedDataTestMode.mode {
            case .printStrings:
                jobRecordClass.printHardcodedJsonDataForConstants()
            case .runTest:
                for (idx, (constant, jsonData)) in jobRecordClass.constants.enumerated() {
                    validateConstantAgainstJsonData(constant: constant, jsonData: jsonData, index: idx)
                }
            }
        }
    }
}

// MARK: - Validatable

extension ValidatableModel where Self: JobRecord {
    func commonValidate(against: Self) throws {
        guard
            label == against.label,
            failureCount == against.failureCount,
            status == against.status,
            exclusiveProcessIdentifier == against.exclusiveProcessIdentifier
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

// MARK: - Job records

extension IncomingContactSyncJobRecord: ValidatableModel {
    static let constants: [(IncomingContactSyncJobRecord, jsonData: Data)] = [
        (
            IncomingContactSyncJobRecord(
                cdnNumber: nil,
                cdnKey: nil,
                encryptionKey: nil,
                digest: nil,
                plaintextLength: nil,
                isCompleteContactSync: true,
                failureCount: 12,
                status: .ready
            ),
            Data(#"{"super":{"failureCount":12,"label":"IncomingContactSync","status":1,"uniqueId":"FF3753B3-B1FD-4B4A-96C3-2398EB120136","recordType":61},"isCompleteContactSync":true,"attachmentId":"darth revan"}"#.utf8)
        ),
        (
            IncomingContactSyncJobRecord(
                cdnNumber: nil,
                cdnKey: nil,
                encryptionKey: nil,
                digest: nil,
                plaintextLength: nil,
                isCompleteContactSync: false,
                failureCount: 6,
                status: .permanentlyFailed
            ),
            Data(#"{"isCompleteContactSync":false,"super":{"uniqueId":"B1341459-3BA3-4AA7-85FF-DECF109A74EA","failureCount":6,"recordType":61,"status":3,"label":"IncomingContactSync"}}"#.utf8)
        ),
        (
            IncomingContactSyncJobRecord(
                cdnNumber: 3,
                cdnKey: "hello",
                encryptionKey: Data(base64Encoded: "mMiOmZhbHNlLCJzdXBlciI6eyJ1b")!,
                digest: Data(base64Encoded: "291bnQiOjYsInJlY29yZFR5cGUiO")!,
                plaintextLength: 55,
                isCompleteContactSync: true
            ),
            Data(#"{"ICSJR_digest":"291bnQiOjYsInJlY29yZFR5cGUiO","ICSJR_plaintextLength":55,"ICSJR_cdnKey":"hello","super":{"status":1,"failureCount":0,"label":"IncomingContactSync","uniqueId":"894EAC5E-918B-434C-A7CE-C24BB8F47932","recordType":61},"ICSJR_cdnNumber":3,"ICSJR_encryptionKey":"mMiOmZhbHNlLCJzdXBlciI6eyJ1b","isCompleteContactSync":true}"#.utf8)
        )
    ]

    func validate(against: IncomingContactSyncJobRecord) throws {
        guard
            isCompleteContactSync == against.isCompleteContactSync
        else {
            throw ValidatableModelError.failedToValidate
        }
        switch (downloadInfo, against.downloadInfo) {
        case (.invalid, .invalid):
            break
        case let (.transient(lhsInfo), .transient(rhsInfo)):
            guard
                lhsInfo == rhsInfo
            else {
                throw ValidatableModelError.failedToValidate
            }
        case (.invalid, _), (.transient, _):
            throw ValidatableModelError.failedToValidate
        }

    }
}

extension LegacyMessageDecryptJobRecord: ValidatableModel {
    static let constants: [(LegacyMessageDecryptJobRecord, jsonData: Data)] = [
        (
            LegacyMessageDecryptJobRecord(
                envelopeData: Data(base64Encoded: "beef")!,
                serverDeliveryTimestamp: 12,
                failureCount: 0,
                status: .ready
            ),
            Data(#"{"super":{"failureCount":0,"label":"SSKMessageDecrypt","status":1,"uniqueId":"0D5C1108-FD33-433F-BCF8-1E2084A864A5","recordType":53},"envelopeData":"beef","serverDeliveryTimestamp":12}"#.utf8)
        ),
        (
            LegacyMessageDecryptJobRecord(
                envelopeData: nil,
                serverDeliveryTimestamp: 12,
                failureCount: 0,
                status: .ready
            ),
            Data(#"{"super":{"failureCount":0,"label":"SSKMessageDecrypt","status":1,"uniqueId":"8F8545C6-0683-4FB4-BDB5-291D5876A09C","recordType":53},"serverDeliveryTimestamp":12}"#.utf8)
        )
    ]

    func validate(against: LegacyMessageDecryptJobRecord) throws {
        guard
            envelopeData == against.envelopeData,
            serverDeliveryTimestamp == against.serverDeliveryTimestamp
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension LocalUserLeaveGroupJobRecord: ValidatableModel {
    static let constants: [(LocalUserLeaveGroupJobRecord, jsonData: Data)] = [
        (
            LocalUserLeaveGroupJobRecord(
                threadId: "the wheels on the bus",
                replacementAdminAci: Aci.constantForTesting("00000000-0000-4000-8000-000000000AAA"),
                waitForMessageProcessing: true,
                failureCount: 40000,
                status: .obsolete
            ),
            Data(#"{"replacementAdminUuid":"00000000-0000-4000-8000-000000000AAA","super":{"failureCount":40000,"label":"LocalUserLeaveGroup","status":4,"uniqueId":"5A4686EC-B396-46BA-8B8C-7FB0F14DB4B1","recordType":74},"threadId":"the wheels on the bus","waitForMessageProcessing":true}"#.utf8)
        ),
        (
            LocalUserLeaveGroupJobRecord(
                threadId: "the wheels on the bus",
                replacementAdminAci: nil,
                waitForMessageProcessing: true,
                failureCount: 40000,
                status: .obsolete
            ),
            Data(#"{"super":{"failureCount":40000,"label":"LocalUserLeaveGroup","status":4,"uniqueId":"2733BF8F-0C66-470B-846D-D23FCE1B8AB9","recordType":74},"threadId":"the wheels on the bus","waitForMessageProcessing":true}"#.utf8)
        )
    ]

    func validate(against: LocalUserLeaveGroupJobRecord) throws {
        guard
            threadId == against.threadId,
            replacementAdminAciString == against.replacementAdminAciString,
            waitForMessageProcessing == against.waitForMessageProcessing
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension MessageSenderJobRecord: ValidatableModel {
    static let constants: [(MessageSenderJobRecord, jsonData: Data)] = [
        (
            MessageSenderJobRecord(
                threadId: "6A860318-BC21-46BC-B1B2-695ED5D6D8A2",
                messageType: .persisted(messageId: "1668418F-4913-4852-8B01-4E5EF8938B33", useMediaQueue: true),
                removeMessageAfterSending: false,
                isHighPriority: true,
                failureCount: UInt(Int.max),
                status: .unknown
            ),
            Data(#"{"messageId":"1668418F-4913-4852-8B01-4E5EF8938B33","isMediaMessage":true,"super":{"failureCount":9223372036854775807,"status":0,"label":"MessageSender","uniqueId":"7695E23B-44CB-4A5A-9012-915CB3E331C1","recordType":35},"removeMessageAfterSending":false,"isHighPriority":true,"threadId":"6A860318-BC21-46BC-B1B2-695ED5D6D8A2"}"#.utf8)
        ),
        (
            MessageSenderJobRecord(
                threadId: nil,
                messageType: .none,
                removeMessageAfterSending: false,
                isHighPriority: true,
                failureCount: UInt(Int.max),
                status: .unknown
            ),
            Data(#"{"removeMessageAfterSending":false,"super":{"failureCount":9223372036854775807,"label":"MessageSender","status":0,"uniqueId":"36064A7A-5EAE-4426-84C1-893EF5864279","recordType":35},"isHighPriority":true,"isMediaMessage":true}"#.utf8)
        ),
        (
            {
                let jobRecord = MessageSenderJobRecord(
                    threadId: "6A860318-BC21-46BC-B1B2-695ED5D6D8A2",
                    messageType: .persisted(messageId: "1668418F-4913-4852-8B01-4E5EF8938B33", useMediaQueue: true),
                    removeMessageAfterSending: false,
                    isHighPriority: true,
                    failureCount: UInt(Int.max),
                    status: .unknown
                )
                jobRecord.exclusiveProcessIdentifier = "abc123"
                return jobRecord
            }(),
            Data(#"{"messageId":"1668418F-4913-4852-8B01-4E5EF8938B33","isMediaMessage":true,"super":{"failureCount":9223372036854775807,"status":0,"label":"MessageSender","uniqueId":"7695E23B-44CB-4A5A-9012-915CB3E331C1","exclusiveProcessIdentifier": "abc123","recordType":35},"removeMessageAfterSending":false,"isHighPriority":true,"threadId":"6A860318-BC21-46BC-B1B2-695ED5D6D8A2"}"#.utf8)
        ),
    ]

    func validate(against: MessageSenderJobRecord) throws {
        guard
            threadId == against.threadId,
            removeMessageAfterSending == against.removeMessageAfterSending,
            isHighPriority == against.isHighPriority
        else {
            throw ValidatableModelError.failedToValidate
        }
        switch (messageType, against.messageType) {
        case let (.persisted(lhsId, lhsUseMediaQueue), .persisted(rhsId, rhsUseMediaQueue)):
            guard
                lhsId == rhsId,
                lhsUseMediaQueue == rhsUseMediaQueue
            else {
                throw ValidatableModelError.failedToValidate
            }
        case let (.editMessage(lhsId, lhsEditMessage, lhsUseMediaQueue), .editMessage(rhsId, rhsEditMessage, rhsUseMediaQueue)):
            guard
                lhsId == rhsId,
                lhsUseMediaQueue == rhsUseMediaQueue,
                lhsEditMessage == rhsEditMessage
            else {
                throw ValidatableModelError.failedToValidate
            }
        case let (.transient(lhsMessage), .transient(rhsMessage)):
            guard
                lhsMessage.uniqueId == rhsMessage.uniqueId
            else {
                throw ValidatableModelError.failedToValidate
            }
        case (.none, .none):
            break
        case
            (.persisted, _),
            (.editMessage, _),
            (.transient, _),
            (.none, _):
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension DonationReceiptCredentialRedemptionJobRecord: ValidatableModel {

    static let constants: [(DonationReceiptCredentialRedemptionJobRecord, jsonData: Data)] = [
        (
            DonationReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "STRIPE",
                paymentMethod: "SEPA_DEBIT",
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
                receiptCredential: nil,
                receiptCredentialPresentation: Data(base64Encoded: "bade")!,
                subscriberID: Data(base64Encoded: "feed")!,
                targetSubscriptionLevel: 12,
                priorSubscriptionLevel: 4,
                isNewSubscription: false,
                shouldSuppressPaymentAlreadyRedeemed: true,
                isBoost: false,
                amount: 0,
                currencyCode: "EUR",
                boostPaymentIntentID: "",
                failureCount: 0,
                status: .ready
            ),
            Data(#"{"targetSubscriptionLevel":12,"currencyCode":"EUR","shouldSuppressPaymentAlreadyRedeemed":true,"priorSubscriptionLevel":4,"paymentMethod":"SEPA_DEBIT","amount":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGjCwwaVSRudWxs1w0ODxAREhMUFRYXGBcWViRjbGFzc1tOUy5tYW50aXNzYVtOUy5uZWdhdGl2ZVtOUy5leHBvbmVudF5OUy5tYW50aXNzYS5ib1lOUy5sZW5ndGhaTlMuY29tcGFjdIACTxAQAAAAAAAAAAAAAAAAAAAAAAgQABABCNIbHB0eWiRjbGFzc25hbWVYJGNsYXNzZXNfEBpOU0RlY2ltYWxOdW1iZXJQbGFjZWhvbGRlcqUfICEiI18QGk5TRGVjaW1hbE51bWJlclBsYWNlaG9sZGVyXxAPTlNEZWNpbWFsTnVtYmVyWE5TTnVtYmVyV05TVmFsdWVYTlNPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAFcAXQBsAHMAfwCLAJcApgCwALsAvQDQANEA0wDVANYA2wDmAO8BDAESAS8BQQFKAVIAAAAAAAACAQAAAAAAAAAkAAAAAAAAAAAAAAAAAAABWw==","subscriberID":"feed","receiptCredentailRequest":"dead","isNewSubscription":false,"super":{"failureCount":0,"label":"SubscriptionReceiptCredentailRedemption","status":1,"uniqueId":"B6A06E3F-51F4-46C5-A3B9-58B1FC54E692","recordType":71},"receiptCredentailRequestContext":"beef","receiptCredentialPresentation":"bade","boostPaymentIntentID":"","paymentProcessor":"STRIPE","isBoost":false}"#.utf8)
        ),
        (
            DonationReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "STRIPE",
                paymentMethod: "SEPA_DEBIT",
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
                receiptCredential: nil,
                receiptCredentialPresentation: Data(base64Encoded: "bade")!,
                subscriberID: Data(base64Encoded: "feed")!,
                targetSubscriptionLevel: 12,
                priorSubscriptionLevel: 4,
                isNewSubscription: false,
                shouldSuppressPaymentAlreadyRedeemed: false,
                isBoost: false,
                amount: 0,
                currencyCode: "EUR",
                boostPaymentIntentID: "",
                failureCount: 0,
                status: .ready
            ),
            Data(#"{"targetSubscriptionLevel":12,"currencyCode":"EUR","shouldSuppressPaymentAlreadyRedeemed":false,"priorSubscriptionLevel":4,"paymentMethod":"SEPA_DEBIT","amount":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGjCwwaVSRudWxs1w0ODxAREhMUFRYXGBcWViRjbGFzc1tOUy5tYW50aXNzYVtOUy5uZWdhdGl2ZVtOUy5leHBvbmVudF5OUy5tYW50aXNzYS5ib1lOUy5sZW5ndGhaTlMuY29tcGFjdIACTxAQAAAAAAAAAAAAAAAAAAAAAAgQABABCNIbHB0eWiRjbGFzc25hbWVYJGNsYXNzZXNfEBpOU0RlY2ltYWxOdW1iZXJQbGFjZWhvbGRlcqUfICEiI18QGk5TRGVjaW1hbE51bWJlclBsYWNlaG9sZGVyXxAPTlNEZWNpbWFsTnVtYmVyWE5TTnVtYmVyV05TVmFsdWVYTlNPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAFcAXQBsAHMAfwCLAJcApgCwALsAvQDQANEA0wDVANYA2wDmAO8BDAESAS8BQQFKAVIAAAAAAAACAQAAAAAAAAAkAAAAAAAAAAAAAAAAAAABWw==","subscriberID":"feed","receiptCredentailRequest":"dead","isNewSubscription":false,"super":{"failureCount":0,"label":"SubscriptionReceiptCredentailRedemption","status":1,"uniqueId":"530EA5D7-3F3C-4741-BB7F-52363CE93343","recordType":71},"receiptCredentailRequestContext":"beef","receiptCredentialPresentation":"bade","boostPaymentIntentID":"","paymentProcessor":"STRIPE","isBoost":false}"#.utf8)
        ),
        (
            DonationReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "STRIPE",
                paymentMethod: "SEPA_DEBIT",
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
                receiptCredential: nil,
                receiptCredentialPresentation: Data(base64Encoded: "bade")!,
                subscriberID: Data(base64Encoded: "feed")!,
                targetSubscriptionLevel: 12,
                priorSubscriptionLevel: 4,
                isNewSubscription: true,
                shouldSuppressPaymentAlreadyRedeemed: false,
                isBoost: true,
                amount: 12.5,
                currencyCode: "USD",
                boostPaymentIntentID: "beep",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(#"{"targetSubscriptionLevel":12,"currencyCode":"USD","shouldSuppressPaymentAlreadyRedeemed":false,"priorSubscriptionLevel":4,"paymentMethod":"SEPA_DEBIT","amount":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGjCwwaVSRudWxs1w0ODxAREhMUFRYXGBgZViRjbGFzc1tOUy5tYW50aXNzYVtOUy5uZWdhdGl2ZVtOUy5leHBvbmVudF5OUy5tYW50aXNzYS5ib1lOUy5sZW5ndGhaTlMuY29tcGFjdIACTxAQfQAAAAAAAAAAAAAAAAAAAAgT\/\/\/\/\/\/\/\/\/\/8QAQnSGxwdHlokY2xhc3NuYW1lWCRjbGFzc2VzXxAaTlNEZWNpbWFsTnVtYmVyUGxhY2Vob2xkZXKlHyAhIiNfEBpOU0RlY2ltYWxOdW1iZXJQbGFjZWhvbGRlcl8QD05TRGVjaW1hbE51bWJlclhOU051bWJlcldOU1ZhbHVlWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBXAF0AbABzAH8AiwCXAKYAsAC7AL0A0ADRANoA3ADdAOIA7QD2ARMBGQE2AUgBUQFZAAAAAAAAAgEAAAAAAAAAJAAAAAAAAAAAAAAAAAAAAWI=","subscriberID":"feed","receiptCredentailRequest":"dead","isNewSubscription":true,"super":{"failureCount":0,"label":"SubscriptionReceiptCredentailRedemption","status":3,"uniqueId":"47BE1A2B-4B10-44E3-BECF-025F7E81F021","recordType":71},"receiptCredentailRequestContext":"beef","receiptCredentialPresentation":"bade","boostPaymentIntentID":"beep","paymentProcessor":"STRIPE","isBoost":true}"#.utf8)
        ),
        (
            DonationReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "bank",
                paymentMethod: nil,
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
                receiptCredential: nil,
                receiptCredentialPresentation: Data(base64Encoded: "bade")!,
                subscriberID: Data(base64Encoded: "feed")!,
                targetSubscriptionLevel: 12,
                priorSubscriptionLevel: 4,
                isNewSubscription: true,
                shouldSuppressPaymentAlreadyRedeemed: false,
                isBoost: true,
                amount: 12.5,
                currencyCode: "shoop",
                boostPaymentIntentID: "de",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(#"{"targetSubscriptionLevel":12,"currencyCode":"shoop","shouldSuppressPaymentAlreadyRedeemed":false,"priorSubscriptionLevel":4,"amount":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGjCwwaVSRudWxs1w0ODxAREhMUFRYXGBgZViRjbGFzc1tOUy5tYW50aXNzYVtOUy5uZWdhdGl2ZVtOUy5leHBvbmVudF5OUy5tYW50aXNzYS5ib1lOUy5sZW5ndGhaTlMuY29tcGFjdIACTxAQfQAAAAAAAAAAAAAAAAAAAAgT\/\/\/\/\/\/\/\/\/\/8QAQnSGxwdHlokY2xhc3NuYW1lWCRjbGFzc2VzXxAaTlNEZWNpbWFsTnVtYmVyUGxhY2Vob2xkZXKlHyAhIiNfEBpOU0RlY2ltYWxOdW1iZXJQbGFjZWhvbGRlcl8QD05TRGVjaW1hbE51bWJlclhOU051bWJlcldOU1ZhbHVlWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBXAF0AbABzAH8AiwCXAKYAsAC7AL0A0ADRANoA3ADdAOIA7QD2ARMBGQE2AUgBUQFZAAAAAAAAAgEAAAAAAAAAJAAAAAAAAAAAAAAAAAAAAWI=","subscriberID":"feed","receiptCredentailRequest":"dead","isNewSubscription":true,"super":{"failureCount":0,"label":"SubscriptionReceiptCredentailRedemption","status":3,"uniqueId":"FCBD3F8D-F23F-4784-9FE4-0D92BFACC28F","recordType":71},"receiptCredentailRequestContext":"beef","receiptCredentialPresentation":"bade","boostPaymentIntentID":"de","paymentProcessor":"bank","isBoost":true}"#.utf8)
        ),
        (
            DonationReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "not svb",
                paymentMethod: nil,
                receiptCredentialRequestContext: Data(base64Encoded: "feeb")!,
                receiptCredentialRequest: Data(base64Encoded: "aded")!,
                receiptCredential: nil,
                receiptCredentialPresentation: nil,
                subscriberID: Data(base64Encoded: "deef")!,
                targetSubscriptionLevel: 12,
                priorSubscriptionLevel: 4,
                isNewSubscription: true,
                shouldSuppressPaymentAlreadyRedeemed: false,
                isBoost: true,
                amount: nil,
                currencyCode: nil,
                boostPaymentIntentID: "na na na na na na na na na na na na na na na na na na na na",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(#"{"subscriberID":"deef","isNewSubscription":true,"shouldSuppressPaymentAlreadyRedeemed":false,"super":{"failureCount":0,"label":"SubscriptionReceiptCredentailRedemption","status":3,"uniqueId":"BCFED95C-5550-42BD-8F0C-69AE5459FC8A","recordType":71},"receiptCredentailRequestContext":"feeb","paymentProcessor":"not svb","targetSubscriptionLevel":12,"priorSubscriptionLevel":4,"receiptCredentailRequest":"aded","isBoost":true,"boostPaymentIntentID":"na na na na na na na na na na na na na na na na na na na na"}"#.utf8)
        ),
        (
            DonationReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "not svb",
                paymentMethod: nil,
                receiptCredentialRequestContext: Data(base64Encoded: "feeb")!,
                receiptCredentialRequest: Data(base64Encoded: "aded")!,
                receiptCredential: Data(base64Encoded: "deda"),
                receiptCredentialPresentation: nil,
                subscriberID: Data(base64Encoded: "deef")!,
                targetSubscriptionLevel: 12,
                priorSubscriptionLevel: 4,
                isNewSubscription: true,
                shouldSuppressPaymentAlreadyRedeemed: false,
                isBoost: true,
                amount: nil,
                currencyCode: nil,
                boostPaymentIntentID: "na na na na na na na na na na na na na na na na na na na na",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(#"{"subscriberID":"deef","isNewSubscription":true,"shouldSuppressPaymentAlreadyRedeemed":false,"super":{"failureCount":0,"label":"SubscriptionReceiptCredentailRedemption","status":3,"uniqueId":"BCFED95C-5550-42BD-8F0C-69AE5459FC8A","recordType":71},"receiptCredentailRequestContext":"feeb","paymentProcessor":"not svb","targetSubscriptionLevel":12,"priorSubscriptionLevel":4,"receiptCredentailRequest":"aded","receiptCredential":"deda","isBoost":true,"boostPaymentIntentID":"na na na na na na na na na na na na na na na na na na na na"}"#.utf8)
        )
    ]

    func validate(against: DonationReceiptCredentialRedemptionJobRecord) throws {
        guard
            paymentProcessor == against.paymentProcessor,
            receiptCredentialRequestContext == against.receiptCredentialRequestContext,
            receiptCredentialRequest == against.receiptCredentialRequest,
            _receiptCredential == against._receiptCredential,
            _receiptCredentialPresentation == against._receiptCredentialPresentation,
            subscriberID == against.subscriberID,
            targetSubscriptionLevel == against.targetSubscriptionLevel,
            priorSubscriptionLevel == against.priorSubscriptionLevel,
            isBoost == against.isBoost,
            amount == against.amount,
            currencyCode == against.currencyCode,
            boostPaymentIntentID == against.boostPaymentIntentID
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension SendGiftBadgeJobRecord: ValidatableModel {
    static let constants: [(SendGiftBadgeJobRecord, jsonData: Data)] = [
        (
            SendGiftBadgeJobRecord(
                paymentProcessor: "money",
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
                amount: 12.6,
                currencyCode: "zhoop",
                paymentIntentClientSecret: "secret",
                paymentIntentId: "yarp",
                paymentMethodId: "carp",
                paypalPayerId: "borp",
                paypalPaymentId: "gorp",
                paypalPaymentToken: "florp",
                threadId: "paul",
                messageText: "blarp",
                failureCount: 9,
                status: .ready
            ),
            Data(#"{"paypalPaymentToken":"florp","threadId":"paul","paymentIntentClientSecret":"secret","amount":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGjCwwaVSRudWxs1w0ODxAREhMUFRYXGBgZViRjbGFzc1tOUy5tYW50aXNzYVtOUy5uZWdhdGl2ZVtOUy5leHBvbmVudF5OUy5tYW50aXNzYS5ib1lOUy5sZW5ndGhaTlMuY29tcGFjdIACTxAQfgAAAAAAAAAAAAAAAAAAAAgT\/\/\/\/\/\/\/\/\/\/8QAQnSGxwdHlokY2xhc3NuYW1lWCRjbGFzc2VzXxAaTlNEZWNpbWFsTnVtYmVyUGxhY2Vob2xkZXKlHyAhIiNfEBpOU0RlY2ltYWxOdW1iZXJQbGFjZWhvbGRlcl8QD05TRGVjaW1hbE51bWJlclhOU051bWJlcldOU1ZhbHVlWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBXAF0AbABzAH8AiwCXAKYAsAC7AL0A0ADRANoA3ADdAOIA7QD2ARMBGQE2AUgBUQFZAAAAAAAAAgEAAAAAAAAAJAAAAAAAAAAAAAAAAAAAAWI=","receiptCredentailRequest":"dead","paymentMethodId":"carp","messageText":"blarp","paypalPayerId":"borp","super":{"failureCount":9,"label":"SendGiftBadge","status":1,"uniqueId":"E39E84CE-CC61-4E1F-95DD-809BA20EA0AC","recordType":73},"boostPaymentIntentID":"yarp","receiptCredentailRequestContext":"beef","paypalPaymentId":"gorp","paymentProcessor":"money","currencyCode":"zhoop"}"#.utf8)
        ),
        (
            SendGiftBadgeJobRecord(
                paymentProcessor: "money",
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
                amount: 12.6,
                currencyCode: "zhoop",
                paymentIntentClientSecret: nil,
                paymentIntentId: nil,
                paymentMethodId: nil,
                paypalPayerId: nil,
                paypalPaymentId: nil,
                paypalPaymentToken: nil,
                threadId: "paul",
                messageText: "blarp",
                failureCount: 9,
                status: .ready
            ),
            Data(#"{"amount":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGjCwwaVSRudWxs1w0ODxAREhMUFRYXGBgZViRjbGFzc1tOUy5tYW50aXNzYVtOUy5uZWdhdGl2ZVtOUy5leHBvbmVudF5OUy5tYW50aXNzYS5ib1lOUy5sZW5ndGhaTlMuY29tcGFjdIACTxAQfgAAAAAAAAAAAAAAAAAAAAgT\/\/\/\/\/\/\/\/\/\/8QAQnSGxwdHlokY2xhc3NuYW1lWCRjbGFzc2VzXxAaTlNEZWNpbWFsTnVtYmVyUGxhY2Vob2xkZXKlHyAhIiNfEBpOU0RlY2ltYWxOdW1iZXJQbGFjZWhvbGRlcl8QD05TRGVjaW1hbE51bWJlclhOU051bWJlcldOU1ZhbHVlWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBXAF0AbABzAH8AiwCXAKYAsAC7AL0A0ADRANoA3ADdAOIA7QD2ARMBGQE2AUgBUQFZAAAAAAAAAgEAAAAAAAAAJAAAAAAAAAAAAAAAAAAAAWI=","super":{"failureCount":9,"label":"SendGiftBadge","status":1,"uniqueId":"A3865D66-C078-4FDF-8557-89859DBA8F07","recordType":73},"receiptCredentailRequestContext":"beef","paymentProcessor":"money","currencyCode":"zhoop","messageText":"blarp","receiptCredentailRequest":"dead","threadId":"paul"}"#.utf8)
        )
    ]

    func validate(against: SendGiftBadgeJobRecord) throws {
        guard
            paymentProcessor == against.paymentProcessor,
            receiptCredentialRequestContext == against.receiptCredentialRequestContext,
            receiptCredentialRequest == against.receiptCredentialRequest,
            amount == against.amount,
            currencyCode == against.currencyCode,
            paymentIntentClientSecret == against.paymentIntentClientSecret,
            paymentIntentId == against.paymentIntentId,
            paymentMethodId == against.paymentMethodId,
            paypalPayerId == against.paypalPayerId,
            paypalPaymentId == against.paypalPaymentId,
            paypalPaymentToken == against.paypalPaymentToken,
            threadId == against.threadId,
            messageText == against.messageText
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension SessionResetJobRecord: ValidatableModel {
    static let constants: [(SessionResetJobRecord, jsonData: Data)] = [
        (
            SessionResetJobRecord(
                contactThreadId: "this",
                failureCount: 14,
                status: .ready
            ),
            Data(#"{"super":{"failureCount":14,"label":"SessionReset","status":1,"uniqueId":"EB87D2DC-9289-455D-B7FC-08ECA4C731CF","recordType":52},"contactThreadId":"this"}"#.utf8)
        )
    ]

    func validate(against: SessionResetJobRecord) throws {
        guard
            contactThreadId == against.contactThreadId
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension CallRecordDeleteAllJobRecord: ValidatableModel {
    static let constants: [(CallRecordDeleteAllJobRecord, jsonData: Data)] = [
        (
            CallRecordDeleteAllJobRecord(
                sendDeleteAllSyncMessage: true,
                deleteAllBeforeCallId: nil,
                deleteAllBeforeConversationId: nil,
                deleteAllBeforeTimestamp: 1234,
                failureCount: 19,
                status: .ready
            ),
            Data(#"{"super":{"label":"CallRecordDeleteAll","uniqueId":"3989CCA4-8C1D-43FC-95C0-C3F59850AE2F","failureCount":19,"recordType":100,"status":1},"CRDAJR_sendDeleteAllSyncMessage":true,"CRDAJR_deleteAllBeforeTimestamp":1234}"#.utf8)
        ),
        (
            CallRecordDeleteAllJobRecord(
                sendDeleteAllSyncMessage: true,
                deleteAllBeforeCallId: 6789,
                deleteAllBeforeConversationId: Aci.constantForTesting("E84A2412-09CB-4EFB-9B1D-3BEB65C14481").serviceIdBinary.asData,
                deleteAllBeforeTimestamp: 1234,
                failureCount: 19,
                status: .ready
            ),
            Data(#"{"CRDAJR_deleteAllBeforeConversationId":"6EokEgnLTvubHTvrZcFEgQ==","CRDAJR_deleteAllBeforeTimestamp":1234,"CRDAJR_deleteAllBeforeCallId":"6789","super":{"label":"CallRecordDeleteAll","status":1,"recordType":100,"failureCount":19,"uniqueId":"C58527B5-C6C8-4CCB-B8FE-AA966A77E8F0"},"CRDAJR_sendDeleteAllSyncMessage":true}"#.utf8)
        ),
        (
            CallRecordDeleteAllJobRecord(
                sendDeleteAllSyncMessage: true,
                deleteAllBeforeCallId: 6789,
                deleteAllBeforeConversationId: Data(repeating: 5, count: 32),
                deleteAllBeforeTimestamp: 1234,
                failureCount: 19,
                status: .ready
            ),
            Data(#"{"super":{"failureCount":19,"recordType":100,"label":"CallRecordDeleteAll","uniqueId":"9C207777-FB9F-463D-9B31-08A1B31E4C33","status":1},"CRDAJR_sendDeleteAllSyncMessage":true,"CRDAJR_deleteAllBeforeTimestamp":1234,"CRDAJR_deleteAllBeforeCallId":"6789","CRDAJR_deleteAllBeforeConversationId":"BQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU="}"#.utf8)
        ),
    ]

    func validate(against: CallRecordDeleteAllJobRecord) throws {
        guard
            sendDeleteAllSyncMessage == against.sendDeleteAllSyncMessage,
            deleteAllBeforeTimestamp == against.deleteAllBeforeTimestamp
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension BulkDeleteInteractionJobRecord: ValidatableModel {
    static let constants: [(BulkDeleteInteractionJobRecord, jsonData: Data)] = [
        (
            BulkDeleteInteractionJobRecord(
                anchorMessageRowId: 12,
                fullThreadDeletionAnchorMessageRowId: 42,
                threadUniqueId: "8279D1D7-EA6F-4D4E-A652-ADBF03DDDF14"
            ),
            Data(#"{"BDIJR_anchorMessageRowId":12,"BDIJR_threadUniqueId":"8279D1D7-EA6F-4D4E-A652-ADBF03DDDF14","BDIJR_fullThreadDeletionAnchorMessageRowId":42,"super":{"failureCount":0,"status":1,"label":"BulkDeleteInteraction","recordType":101,"uniqueId":"E01CD6F0-A3B2-4AC6-8014-9DAFBC36EB63"}}"#.utf8)
        )
    ]

    func validate(against: BulkDeleteInteractionJobRecord) throws {
        guard
            anchorMessageRowId == against.anchorMessageRowId,
            fullThreadDeletionAnchorMessageRowId == against.fullThreadDeletionAnchorMessageRowId,
            threadUniqueId == against.threadUniqueId
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

/// These are hard to generate constants for, becuase they're strongly-typed
/// with real LibSignal `ReceiptCredential*`s.
extension BackupReceiptCredentialRedemptionJobRecord: ValidatableModel {
    static let constants: [(BackupReceiptCredentialRedemptionJobRecord, jsonData: Data)] = []

    func validate(against: BackupReceiptCredentialRedemptionJobRecord) throws {
        throw ValidatableModelError.failedToValidate
    }
}
