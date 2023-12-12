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
        case .broadcastMediaMessage: return BroadcastMediaMessageJobRecord.self
        case .incomingContactSync: return IncomingContactSyncJobRecord.self
        case .deprecated_incomingGroupSync: return IncomingGroupSyncJobRecord.self
        case .legacyMessageDecrypt: return LegacyMessageDecryptJobRecord.self
        case .localUserLeaveGroup: return LocalUserLeaveGroupJobRecord.self
        case .messageSender: return MessageSenderJobRecord.self
        case .receiptCredentialRedemption: return ReceiptCredentialRedemptionJobRecord.self
        case .sendGiftBadge: return SendGiftBadgeJobRecord.self
        case .sessionReset: return SessionResetJobRecord.self
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

extension BroadcastMediaMessageJobRecord: ValidatableModel {
    static let constants: [(BroadcastMediaMessageJobRecord, base64JsonData: Data)] = [
        (
            BroadcastMediaMessageJobRecord(
                attachmentIdMap: ["once": ["upon", "a"]],
                unsavedMessagesToSend: [
                    .init(uniqueId: "time", thread: TSThread(uniqueId: "in a galaxy"))
                ],
                exclusiveProcessIdentifier: nil,
                failureCount: 3,
                status: .running
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjMsImxhYmVsIjoiQnJvYWRjYXN0TWVkaWFNZXNzYWdlIiwic3RhdHVzIjoyLCJ1bmlxdWVJZCI6IkY1QjMzODBDLUI0REItNDVERS1CQjA3LUNDNkJDQUU5N0ZEQiIsInJlY29yZFR5cGUiOjU4fSwiYXR0YWNobWVudElkTWFwIjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHb0N3d1ZGaHNjSFNOVkpHNTFiR3pURFE0UEVCSVVWMDVUTG10bGVYTmFUbE11YjJKcVpXTjBjMVlrWTJ4aGMzT2hFWUFDb1JPQUE0QUhWRzl1WTJYU0RnOFhHcUlZR1lBRWdBV0FCbFIxY0c5dVVXSFNIaDhnSVZva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelYwNVRRWEp5WVhtaUlDSllUbE5QWW1wbFkzVFNIaDhrSlZ4T1UwUnBZM1JwYjI1aGNubWlKaUpjVGxORWFXTjBhVzl1WVhKNUNCRWFKQ2t5TjBsTVVWTmNZbWx4ZklPRmg0bUxqWktYbXB5ZW9LV25yTGZBeU12VTJlYnBBQUFBQUFBQUFRRUFBQUFBQUFBQUp3QUFBQUFBQUFBQUFBQUFBQUFBQVBZPSIsInVuc2F2ZWRNZXNzYWdlc1RvU2VuZCI6IlluQnNhWE4wTUREVUFRSURCQVVHQndwWUpIWmxjbk5wYjI1WkpHRnlZMmhwZG1WeVZDUjBiM0JZSkc5aWFtVmpkSE1TQUFHR29GOFFEMDVUUzJWNVpXUkJjbU5vYVhabGN0RUlDVlJ5YjI5MGdBR3FDd3dTUmtkSVNVcExWMVVrYm5Wc2JOSU5EZzhSV2s1VExtOWlhbVZqZEhOV0pHTnNZWE56b1JDQUFvQUozeEFhRXhRVkZnNFhHQmthR3h3ZEhoOGdJU0lqSkNVbUp5Z3BLaXNzTFMwc01DMHNNeTBzTFN3c0xDd3RMU3d0TEN4QlFpd3RMVjhRRTNKbFkyVnBkbVZrUVhSVWFXMWxjM1JoYlhCZkVCSnBjMVpwWlhkUGJtTmxRMjl0Y0d4bGRHVmZFQnh6ZEc5eVpXUlRhRzkxYkdSVGRHRnlkRVY0Y0dseVpWUnBiV1Z5WHhBUFpYaHdhWEpsVTNSaGNuUmxaRUYwWHhBUmFYTldhV1YzVDI1alpVMWxjM05oWjJWZkVBOU5WRXhOYjJSbGJGWmxjbk5wYjI1ZWRXNXBjWFZsVkdoeVpXRmtTV1JmRUJWb1lYTk1aV2RoWTNsTlpYTnpZV2RsVTNSaGRHVldjMjl5ZEVsa1h4QVNhWE5HY205dFRHbHVhMlZrUkdWMmFXTmxYeEFjYjNWMFoyOXBibWROWlhOellXZGxVMk5vWlcxaFZtVnljMmx2Ymw4UUVHVjRjR2x5WlhOSmJsTmxZMjl1WkhOZkVCQm5jbTkxY0UxbGRHRk5aWE56WVdkbFh4QVNiR1ZuWVdONVRXVnpjMkZuWlZOMFlYUmxYeEFTYkdWbllXTjVWMkZ6UkdWc2FYWmxjbVZrWG1selZtOXBZMlZOWlhOellXZGxXV1Y0Y0dseVpYTkJkRjhRRVdselIzSnZkWEJUZEc5eWVWSmxjR3g1WFhOamFHVnRZVlpsY25OcGIyNVpaV1JwZEZOMFlYUmxXWFJwYldWemRHRnRjRmgxYm1seGRXVkpaRjhRRW5OMGIzSmxaRTFsYzNOaFoyVlRkR0YwWlY4UUVuZGhjMUpsYlc5MFpXeDVSR1ZzWlhSbFpGOFFFMmhoYzFONWJtTmxaRlJ5WVc1elkzSnBjSFNBQTRBRWdBU0FBNEFJZ0FTQUE0QUZnQVNBQTRBRWdBT0FBNEFEZ0FPQUJJQUVnQU9BQklBRGdBT0FCNEFHZ0FPQUJJQUVFQUFJVzJsdUlHRWdaMkZzWVhoNVZIUnBiV1VUQUFBQmpEYzAxV1hTVEUxT1Qxb2tZMnhoYzNOdVlXMWxXQ1JqYkdGemMyVnpYeEFSVkZOUGRYUm5iMmx1WjAxbGMzTmhaMlduVUZGU1UxUlZWbDhRRVZSVFQzVjBaMjlwYm1kTlpYTnpZV2RsV1ZSVFRXVnpjMkZuWlYxVVUwbHVkR1Z5WVdOMGFXOXVXVUpoYzJWTmIyUmxiRjhRRTFSVFdXRndSR0YwWVdKaGMyVlBZbXBsWTNSWVRWUk1UVzlrWld4WVRsTlBZbXBsWTNUU1RFMVlXVmRPVTBGeWNtRjVvbGhXQUFnQUVRQWFBQ1FBS1FBeUFEY0FTUUJNQUZFQVV3QmVBR1FBYVFCMEFIc0FmUUJcL0FJRUF1QURPQU9NQkFnRVVBU2dCT2dGSkFXRUJhQUY5QVp3QnJ3SENBZGNCN0FIN0FnVUNHUUluQWpFQ093SkVBbGtDYmdLRUFvWUNpQUtLQW93Q2pnS1FBcElDbEFLV0FwZ0NtZ0tjQXA0Q29BS2lBcVFDcGdLb0Fxb0NyQUt1QXJBQ3NnSzBBcllDdUFLNkFyc0N4d0xNQXRVQzJnTGxBdTREQWdNS0F4NERLQU0yQTBBRFZnTmZBMmdEYlFOMUFBQUFBQUFBQWdFQUFBQUFBQUFBV2dBQUFBQUFBQUFBQUFBQUFBQUFBM2c9In0=")!
        ),
        (
            BroadcastMediaMessageJobRecord(
                attachmentIdMap: ["once": ["upon", "a"]],
                unsavedMessagesToSend: nil,
                exclusiveProcessIdentifier: nil,
                failureCount: 3,
                status: .running
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjMsImxhYmVsIjoiQnJvYWRjYXN0TWVkaWFNZXNzYWdlIiwic3RhdHVzIjoyLCJ1bmlxdWVJZCI6IjNFQjkwNDM1LTkwNEEtNDZEQS05NTFELUFGNTc3QjM4QURENyIsInJlY29yZFR5cGUiOjU4fSwiYXR0YWNobWVudElkTWFwIjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHb0N3d1ZGaHNjSFNOVkpHNTFiR3pURFE0UEVCSVVWMDVUTG10bGVYTmFUbE11YjJKcVpXTjBjMVlrWTJ4aGMzT2hFWUFDb1JPQUE0QUhWRzl1WTJYU0RnOFhHcUlZR1lBRWdBV0FCbFIxY0c5dVVXSFNIaDhnSVZva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelYwNVRRWEp5WVhtaUlDSllUbE5QWW1wbFkzVFNIaDhrSlZ4T1UwUnBZM1JwYjI1aGNubWlKaUpjVGxORWFXTjBhVzl1WVhKNUNCRWFKQ2t5TjBsTVVWTmNZbWx4ZklPRmg0bUxqWktYbXB5ZW9LV25yTGZBeU12VTJlYnBBQUFBQUFBQUFRRUFBQUFBQUFBQUp3QUFBQUFBQUFBQUFBQUFBQUFBQVBZPSJ9")!
        )
    ]

    func validate(against: BroadcastMediaMessageJobRecord) throws {
        guard
            attachmentIdMap == against.attachmentIdMap,
            unsavedMessagesToSend?.count == against.unsavedMessagesToSend?.count,
            unsavedMessagesToSend?.first?.uniqueId == against.unsavedMessagesToSend?.first?.uniqueId
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension IncomingContactSyncJobRecord: ValidatableModel {
    static let constants: [(IncomingContactSyncJobRecord, base64JsonData: Data)] = [
        (
            IncomingContactSyncJobRecord(
                attachmentId: "darth revan",
                isCompleteContactSync: true,
                exclusiveProcessIdentifier: "star wars character",
                failureCount: 12,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjEyLCJsYWJlbCI6IkluY29taW5nQ29udGFjdFN5bmMiLCJzdGF0dXMiOjEsInVuaXF1ZUlkIjoiRkYzNzUzQjMtQjFGRC00QjRBLTk2QzMtMjM5OEVCMTIwMTM2IiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJzdGFyIHdhcnMgY2hhcmFjdGVyIiwicmVjb3JkVHlwZSI6NjF9LCJpc0NvbXBsZXRlQ29udGFjdFN5bmMiOnRydWUsImF0dGFjaG1lbnRJZCI6ImRhcnRoIHJldmFuIn0=")!
        )
    ]

    func validate(against: IncomingContactSyncJobRecord) throws {
        guard
            attachmentId == against.attachmentId,
            isCompleteContactSync == against.isCompleteContactSync
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension IncomingGroupSyncJobRecord: ValidatableModel {
    static let constants: [(IncomingGroupSyncJobRecord, base64JsonData: Data)] = [
        (
            IncomingGroupSyncJobRecord(
                attachmentId: "happy birthday",
                exclusiveProcessIdentifier: "happy birthday TO YOOOU",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjAsImxhYmVsIjoiSW5jb21pbmdHcm91cFN5bmMiLCJzdGF0dXMiOjMsInVuaXF1ZUlkIjoiRUU0RTgwMDQtODVEMC00OTg0LUE1REItMDhCQURBNkQyNkI1IiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJoYXBweSBiaXJ0aGRheSBUTyBZT09PVSIsInJlY29yZFR5cGUiOjYwfSwiYXR0YWNobWVudElkIjoiaGFwcHkgYmlydGhkYXkifQ==")!
        )
    ]

    func validate(against: IncomingGroupSyncJobRecord) throws {
        guard
            attachmentId == against.attachmentId
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension LegacyMessageDecryptJobRecord: ValidatableModel {
    static let constants: [(LegacyMessageDecryptJobRecord, base64JsonData: Data)] = [
        (
            LegacyMessageDecryptJobRecord(
                envelopeData: Data(base64Encoded: "beef")!,
                serverDeliveryTimestamp: 12,
                exclusiveProcessIdentifier: "give you up",
                failureCount: 0,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjAsImxhYmVsIjoiU1NLTWVzc2FnZURlY3J5cHQiLCJzdGF0dXMiOjEsInVuaXF1ZUlkIjoiMEQ1QzExMDgtRkQzMy00MzNGLUJDRjgtMUUyMDg0QTg2NEE1IiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJnaXZlIHlvdSB1cCIsInJlY29yZFR5cGUiOjUzfSwiZW52ZWxvcGVEYXRhIjoiYmVlZiIsInNlcnZlckRlbGl2ZXJ5VGltZXN0YW1wIjoxMn0=")!
        ),
        (
            LegacyMessageDecryptJobRecord(
                envelopeData: nil,
                serverDeliveryTimestamp: 12,
                exclusiveProcessIdentifier: "give you up",
                failureCount: 0,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjAsImxhYmVsIjoiU1NLTWVzc2FnZURlY3J5cHQiLCJzdGF0dXMiOjEsInVuaXF1ZUlkIjoiOEY4NTQ1QzYtMDY4My00RkI0LUJEQjUtMjkxRDU4NzZBMDlDIiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJnaXZlIHlvdSB1cCIsInJlY29yZFR5cGUiOjUzfSwic2VydmVyRGVsaXZlcnlUaW1lc3RhbXAiOjEyfQ==")!
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
    static let constants: [(LocalUserLeaveGroupJobRecord, base64JsonData: Data)] = [
        (
            LocalUserLeaveGroupJobRecord(
                threadId: "the wheels on the bus",
                replacementAdminAci: Aci.constantForTesting("00000000-0000-4000-8000-000000000AAA"),
                waitForMessageProcessing: true,
                exclusiveProcessIdentifier: "round and round!",
                failureCount: 40000,
                status: .obsolete
            ),
            Data(base64Encoded: "eyJyZXBsYWNlbWVudEFkbWluVXVpZCI6IjAwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMEFBQSIsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6NDAwMDAsImxhYmVsIjoiTG9jYWxVc2VyTGVhdmVHcm91cCIsInN0YXR1cyI6NCwidW5pcXVlSWQiOiI1QTQ2ODZFQy1CMzk2LTQ2QkEtOEI4Qy03RkIwRjE0REI0QjEiLCJleGNsdXNpdmVQcm9jZXNzSWRlbnRpZmllciI6InJvdW5kIGFuZCByb3VuZCEiLCJyZWNvcmRUeXBlIjo3NH0sInRocmVhZElkIjoidGhlIHdoZWVscyBvbiB0aGUgYnVzIiwid2FpdEZvck1lc3NhZ2VQcm9jZXNzaW5nIjp0cnVlfQ==")!
        ),
        (
            LocalUserLeaveGroupJobRecord(
                threadId: "the wheels on the bus",
                replacementAdminAci: nil,
                waitForMessageProcessing: true,
                exclusiveProcessIdentifier: "round and round!",
                failureCount: 40000,
                status: .obsolete
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjQwMDAwLCJsYWJlbCI6IkxvY2FsVXNlckxlYXZlR3JvdXAiLCJzdGF0dXMiOjQsInVuaXF1ZUlkIjoiMjczM0JGOEYtMEM2Ni00NzBCLTg0NkQtRDIzRkNFMUI4QUI5IiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJyb3VuZCBhbmQgcm91bmQhIiwicmVjb3JkVHlwZSI6NzR9LCJ0aHJlYWRJZCI6InRoZSB3aGVlbHMgb24gdGhlIGJ1cyIsIndhaXRGb3JNZXNzYWdlUHJvY2Vzc2luZyI6dHJ1ZX0=")!
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
    static let constants: [(MessageSenderJobRecord, base64JsonData: Data)] = [
        (
            MessageSenderJobRecord(
                messageId: "houston",
                threadId: "we",
                invisibleMessage: TSOutgoingMessage(
                    uniqueId: "have",
                    thread: .init(uniqueId: "a")
                ),
                isMediaMessage: true,
                removeMessageAfterSending: false,
                isHighPriority: true,
                exclusiveProcessIdentifier: nil,
                failureCount: UInt(Int.max),
                status: .unknown
            ),
            Data(base64Encoded: "eyJtZXNzYWdlSWQiOiJob3VzdG9uIiwidGhyZWFkSWQiOiJ3ZSIsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6OTIyMzM3MjAzNjg1NDc3NTgwNywibGFiZWwiOiJNZXNzYWdlU2VuZGVyIiwic3RhdHVzIjowLCJ1bmlxdWVJZCI6IkI3MjkyODkwLTlEMzktNDY1MC05OEVCLTA4QjcxRTVGOTk1OSIsInJlY29yZFR5cGUiOjM1fSwicmVtb3ZlTWVzc2FnZUFmdGVyU2VuZGluZyI6ZmFsc2UsImlzSGlnaFByaW9yaXR5Ijp0cnVlLCJpbnZpc2libGVNZXNzYWdlIjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHb0N3eEJRa05FUlVaVkpHNTFiR3pmRUJvTkRnOFFFUklURkJVV0Z4Z1pHaHNjSFI0ZklDRWlJeVFsSmljb0tDY3JLQ2N1S0Njb0p5Y25KeWdvSnlnbkp6dzlKeWdvWHhBVGNtVmpaV2wyWldSQmRGUnBiV1Z6ZEdGdGNGOFFFbWx6Vm1sbGQwOXVZMlZEYjIxd2JHVjBaVjhRSEhOMGIzSmxaRk5vYjNWc1pGTjBZWEowUlhod2FYSmxWR2x0WlhKZkVBOWxlSEJwY21WVGRHRnlkR1ZrUVhSV0pHTnNZWE56WHhBUmFYTldhV1YzVDI1alpVMWxjM05oWjJWZkVBOU5WRXhOYjJSbGJGWmxjbk5wYjI1ZWRXNXBjWFZsVkdoeVpXRmtTV1JmRUJWb1lYTk1aV2RoWTNsTlpYTnpZV2RsVTNSaGRHVldjMjl5ZEVsa1h4QVNhWE5HY205dFRHbHVhMlZrUkdWMmFXTmxYeEFjYjNWMFoyOXBibWROWlhOellXZGxVMk5vWlcxaFZtVnljMmx2Ymw4UUVHVjRjR2x5WlhOSmJsTmxZMjl1WkhOZkVCQm5jbTkxY0UxbGRHRk5aWE56WVdkbFh4QVNiR1ZuWVdONVRXVnpjMkZuWlZOMFlYUmxYeEFTYkdWbllXTjVWMkZ6UkdWc2FYWmxjbVZrWG1selZtOXBZMlZOWlhOellXZGxXV1Y0Y0dseVpYTkJkRjhRRVdselIzSnZkWEJUZEc5eWVWSmxjR3g1WFhOamFHVnRZVlpsY25OcGIyNVpaV1JwZEZOMFlYUmxXWFJwYldWemRHRnRjRmgxYm1seGRXVkpaRjhRRW5OMGIzSmxaRTFsYzNOaFoyVlRkR0YwWlY4UUVuZGhjMUpsYlc5MFpXeDVSR1ZzWlhSbFpGOFFFMmhoYzFONWJtTmxaRlJ5WVc1elkzSnBjSFNBQW9BRGdBT0FBb0FIZ0FPQUFvQUVnQU9BQW9BRGdBS0FBb0FDZ0FLQUE0QURnQUtBQTRBQ2dBS0FCb0FGZ0FLQUE0QURFQUFJVVdGVWFHRjJaUk1BQUFHTU56VFZlTkpIU0VsS1dpUmpiR0Z6YzI1aGJXVllKR05zWVhOelpYTmZFQkZVVTA5MWRHZHZhVzVuVFdWemMyRm5aYWRMVEUxT1QxQlJYeEFSVkZOUGRYUm5iMmx1WjAxbGMzTmhaMlZaVkZOTlpYTnpZV2RsWFZSVFNXNTBaWEpoWTNScGIyNVpRbUZ6WlUxdlpHVnNYeEFUVkZOWllYQkVZWFJoWW1GelpVOWlhbVZqZEZoTlZFeE5iMlJsYkZoT1UwOWlhbVZqZEFBSUFCRUFHZ0FrQUNrQU1nQTNBRWtBVEFCUkFGTUFYQUJpQUprQXJ3REVBT01BOVFEOEFSQUJJZ0V4QVVrQlVBRmxBWVFCbHdHcUFiOEIxQUhqQWUwQ0FRSVBBaGtDSXdJc0FrRUNWZ0pzQW00Q2NBSnlBblFDZGdKNEFub0NmQUorQW9BQ2dnS0VBb1lDaUFLS0Fvd0NqZ0tRQXBJQ2xBS1dBcGdDbWdLY0FwNENvQUtpQXFNQ3BRS3FBck1DdUFMREFzd0M0QUxvQXZ3REJnTVVBeDRETkFNOUFBQUFBQUFBQWdFQUFBQUFBQUFBVWdBQUFBQUFBQUFBQUFBQUFBQUFBMFk9IiwiaXNNZWRpYU1lc3NhZ2UiOnRydWV9")!
        ),
        (
            MessageSenderJobRecord(
                messageId: nil,
                threadId: nil,
                invisibleMessage: nil,
                isMediaMessage: true,
                removeMessageAfterSending: false,
                isHighPriority: true,
                exclusiveProcessIdentifier: nil,
                failureCount: UInt(Int.max),
                status: .unknown
            ),
            Data(base64Encoded: "eyJyZW1vdmVNZXNzYWdlQWZ0ZXJTZW5kaW5nIjpmYWxzZSwic3VwZXIiOnsiZmFpbHVyZUNvdW50Ijo5MjIzMzcyMDM2ODU0Nzc1ODA3LCJsYWJlbCI6Ik1lc3NhZ2VTZW5kZXIiLCJzdGF0dXMiOjAsInVuaXF1ZUlkIjoiMzYwNjRBN0EtNUVBRS00NDI2LTg0QzEtODkzRUY1ODY0Mjc5IiwicmVjb3JkVHlwZSI6MzV9LCJpc0hpZ2hQcmlvcml0eSI6dHJ1ZSwiaXNNZWRpYU1lc3NhZ2UiOnRydWV9")!
        )
    ]

    func validate(against: MessageSenderJobRecord) throws {
        guard
            messageId == against.messageId,
            threadId == against.threadId,
            isMediaMessage == against.isMediaMessage,
            invisibleMessage?.uniqueId == against.invisibleMessage?.uniqueId,
            removeMessageAfterSending == against.removeMessageAfterSending,
            isHighPriority == against.isHighPriority
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension ReceiptCredentialRedemptionJobRecord: ValidatableModel {

    static let constants: [(ReceiptCredentialRedemptionJobRecord, base64JsonData: Data)] = [
        (
            ReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "STRIPE",
                paymentMethod: "SEPA_DEBIT",
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
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
                exclusiveProcessIdentifier: nil,
                failureCount: 0,
                status: .ready
            ),
            Data(base64Encoded: "eyJ0YXJnZXRTdWJzY3JpcHRpb25MZXZlbCI6MTIsImN1cnJlbmN5Q29kZSI6IkVVUiIsInNob3VsZFN1cHByZXNzUGF5bWVudEFscmVhZHlSZWRlZW1lZCI6dHJ1ZSwicHJpb3JTdWJzY3JpcHRpb25MZXZlbCI6NCwicGF5bWVudE1ldGhvZCI6IlNFUEFfREVCSVQiLCJhbW91bnQiOiJZbkJzYVhOME1ERFVBUUlEQkFVR0J3cFlKSFpsY25OcGIyNVpKR0Z5WTJocGRtVnlWQ1IwYjNCWUpHOWlhbVZqZEhNU0FBR0dvRjhRRDA1VFMyVjVaV1JCY21Ob2FYWmxjdEVJQ1ZSeWIyOTBnQUdqQ3d3YVZTUnVkV3hzMXcwT0R4QVJFaE1VRlJZWEdCY1dWaVJqYkdGemMxdE9VeTV0WVc1MGFYTnpZVnRPVXk1dVpXZGhkR2wyWlZ0T1V5NWxlSEJ2Ym1WdWRGNU9VeTV0WVc1MGFYTnpZUzVpYjFsT1V5NXNaVzVuZEdoYVRsTXVZMjl0Y0dGamRJQUNUeEFRQUFBQUFBQUFBQUFBQUFBQUFBQUFBQWdRQUJBQkNOSWJIQjBlV2lSamJHRnpjMjVoYldWWUpHTnNZWE56WlhOZkVCcE9VMFJsWTJsdFlXeE9kVzFpWlhKUWJHRmpaV2h2YkdSbGNxVWZJQ0VpSTE4UUdrNVRSR1ZqYVcxaGJFNTFiV0psY2xCc1lXTmxhRzlzWkdWeVh4QVBUbE5FWldOcGJXRnNUblZ0WW1WeVdFNVRUblZ0WW1WeVYwNVRWbUZzZFdWWVRsTlBZbXBsWTNRQUNBQVJBQm9BSkFBcEFESUFOd0JKQUV3QVVRQlRBRmNBWFFCc0FITUFmd0NMQUpjQXBnQ3dBTHNBdlFEUUFORUEwd0RWQU5ZQTJ3RG1BTzhCREFFU0FTOEJRUUZLQVZJQUFBQUFBQUFDQVFBQUFBQUFBQUFrQUFBQUFBQUFBQUFBQUFBQUFBQUJXdz09Iiwic3Vic2NyaWJlcklEIjoiZmVlZCIsInJlY2VpcHRDcmVkZW50YWlsUmVxdWVzdCI6ImRlYWQiLCJpc05ld1N1YnNjcmlwdGlvbiI6ZmFsc2UsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6MCwibGFiZWwiOiJTdWJzY3JpcHRpb25SZWNlaXB0Q3JlZGVudGFpbFJlZGVtcHRpb24iLCJzdGF0dXMiOjEsInVuaXF1ZUlkIjoiQjZBMDZFM0YtNTFGNC00NkM1LUEzQjktNThCMUZDNTRFNjkyIiwicmVjb3JkVHlwZSI6NzF9LCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3RDb250ZXh0IjoiYmVlZiIsInJlY2VpcHRDcmVkZW50aWFsUHJlc2VudGF0aW9uIjoiYmFkZSIsImJvb3N0UGF5bWVudEludGVudElEIjoiIiwicGF5bWVudFByb2Nlc3NvciI6IlNUUklQRSIsImlzQm9vc3QiOmZhbHNlfQ==")!
        ),
        (
            ReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "STRIPE",
                paymentMethod: "SEPA_DEBIT",
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
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
                exclusiveProcessIdentifier: nil,
                failureCount: 0,
                status: .ready
            ),
            Data(base64Encoded: "eyJ0YXJnZXRTdWJzY3JpcHRpb25MZXZlbCI6MTIsImN1cnJlbmN5Q29kZSI6IkVVUiIsInNob3VsZFN1cHByZXNzUGF5bWVudEFscmVhZHlSZWRlZW1lZCI6ZmFsc2UsInByaW9yU3Vic2NyaXB0aW9uTGV2ZWwiOjQsInBheW1lbnRNZXRob2QiOiJTRVBBX0RFQklUIiwiYW1vdW50IjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHakN3d2FWU1J1ZFd4czF3ME9EeEFSRWhNVUZSWVhHQmNXVmlSamJHRnpjMXRPVXk1dFlXNTBhWE56WVZ0T1V5NXVaV2RoZEdsMlpWdE9VeTVsZUhCdmJtVnVkRjVPVXk1dFlXNTBhWE56WVM1aWIxbE9VeTVzWlc1bmRHaGFUbE11WTI5dGNHRmpkSUFDVHhBUUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFnUUFCQUJDTkliSEIwZVdpUmpiR0Z6YzI1aGJXVllKR05zWVhOelpYTmZFQnBPVTBSbFkybHRZV3hPZFcxaVpYSlFiR0ZqWldodmJHUmxjcVVmSUNFaUkxOFFHazVUUkdWamFXMWhiRTUxYldKbGNsQnNZV05sYUc5c1pHVnlYeEFQVGxORVpXTnBiV0ZzVG5WdFltVnlXRTVUVG5WdFltVnlWMDVUVm1Gc2RXVllUbE5QWW1wbFkzUUFDQUFSQUJvQUpBQXBBRElBTndCSkFFd0FVUUJUQUZjQVhRQnNBSE1BZndDTEFKY0FwZ0N3QUxzQXZRRFFBTkVBMHdEVkFOWUEyd0RtQU84QkRBRVNBUzhCUVFGS0FWSUFBQUFBQUFBQ0FRQUFBQUFBQUFBa0FBQUFBQUFBQUFBQUFBQUFBQUFCV3c9PSIsInN1YnNjcmliZXJJRCI6ImZlZWQiLCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3QiOiJkZWFkIiwiaXNOZXdTdWJzY3JpcHRpb24iOmZhbHNlLCJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjAsImxhYmVsIjoiU3Vic2NyaXB0aW9uUmVjZWlwdENyZWRlbnRhaWxSZWRlbXB0aW9uIiwic3RhdHVzIjoxLCJ1bmlxdWVJZCI6IjUzMEVBNUQ3LTNGM0MtNDc0MS1CQjdGLTUyMzYzQ0U5MzM0MyIsInJlY29yZFR5cGUiOjcxfSwicmVjZWlwdENyZWRlbnRhaWxSZXF1ZXN0Q29udGV4dCI6ImJlZWYiLCJyZWNlaXB0Q3JlZGVudGlhbFByZXNlbnRhdGlvbiI6ImJhZGUiLCJib29zdFBheW1lbnRJbnRlbnRJRCI6IiIsInBheW1lbnRQcm9jZXNzb3IiOiJTVFJJUEUiLCJpc0Jvb3N0IjpmYWxzZX0=")!
        ),
        (
            ReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "STRIPE",
                paymentMethod: "SEPA_DEBIT",
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
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
                exclusiveProcessIdentifier: "bing",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(base64Encoded: "eyJ0YXJnZXRTdWJzY3JpcHRpb25MZXZlbCI6MTIsImN1cnJlbmN5Q29kZSI6IlVTRCIsInNob3VsZFN1cHByZXNzUGF5bWVudEFscmVhZHlSZWRlZW1lZCI6ZmFsc2UsInByaW9yU3Vic2NyaXB0aW9uTGV2ZWwiOjQsInBheW1lbnRNZXRob2QiOiJTRVBBX0RFQklUIiwiYW1vdW50IjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHakN3d2FWU1J1ZFd4czF3ME9EeEFSRWhNVUZSWVhHQmdaVmlSamJHRnpjMXRPVXk1dFlXNTBhWE56WVZ0T1V5NXVaV2RoZEdsMlpWdE9VeTVsZUhCdmJtVnVkRjVPVXk1dFlXNTBhWE56WVM1aWIxbE9VeTVzWlc1bmRHaGFUbE11WTI5dGNHRmpkSUFDVHhBUWZRQUFBQUFBQUFBQUFBQUFBQUFBQUFnVFwvXC9cL1wvXC9cL1wvXC9cL1wvOFFBUW5TR3h3ZEhsb2tZMnhoYzNOdVlXMWxXQ1JqYkdGemMyVnpYeEFhVGxORVpXTnBiV0ZzVG5WdFltVnlVR3hoWTJWb2IyeGtaWEtsSHlBaElpTmZFQnBPVTBSbFkybHRZV3hPZFcxaVpYSlFiR0ZqWldodmJHUmxjbDhRRDA1VFJHVmphVzFoYkU1MWJXSmxjbGhPVTA1MWJXSmxjbGRPVTFaaGJIVmxXRTVUVDJKcVpXTjBBQWdBRVFBYUFDUUFLUUF5QURjQVNRQk1BRkVBVXdCWEFGMEFiQUJ6QUg4QWl3Q1hBS1lBc0FDN0FMMEEwQURSQU5vQTNBRGRBT0lBN1FEMkFSTUJHUUUyQVVnQlVRRlpBQUFBQUFBQUFnRUFBQUFBQUFBQUpBQUFBQUFBQUFBQUFBQUFBQUFBQVdJPSIsInN1YnNjcmliZXJJRCI6ImZlZWQiLCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3QiOiJkZWFkIiwiaXNOZXdTdWJzY3JpcHRpb24iOnRydWUsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6MCwibGFiZWwiOiJTdWJzY3JpcHRpb25SZWNlaXB0Q3JlZGVudGFpbFJlZGVtcHRpb24iLCJzdGF0dXMiOjMsInVuaXF1ZUlkIjoiNDdCRTFBMkItNEIxMC00NEUzLUJFQ0YtMDI1RjdFODFGMDIxIiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJiaW5nIiwicmVjb3JkVHlwZSI6NzF9LCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3RDb250ZXh0IjoiYmVlZiIsInJlY2VpcHRDcmVkZW50aWFsUHJlc2VudGF0aW9uIjoiYmFkZSIsImJvb3N0UGF5bWVudEludGVudElEIjoiYmVlcCIsInBheW1lbnRQcm9jZXNzb3IiOiJTVFJJUEUiLCJpc0Jvb3N0Ijp0cnVlfQ==")!
        ),
        (
            ReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "bank",
                paymentMethod: nil,
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
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
                exclusiveProcessIdentifier: "da boop",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(base64Encoded: "eyJ0YXJnZXRTdWJzY3JpcHRpb25MZXZlbCI6MTIsImN1cnJlbmN5Q29kZSI6InNob29wIiwic2hvdWxkU3VwcHJlc3NQYXltZW50QWxyZWFkeVJlZGVlbWVkIjpmYWxzZSwicHJpb3JTdWJzY3JpcHRpb25MZXZlbCI6NCwiYW1vdW50IjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHakN3d2FWU1J1ZFd4czF3ME9EeEFSRWhNVUZSWVhHQmdaVmlSamJHRnpjMXRPVXk1dFlXNTBhWE56WVZ0T1V5NXVaV2RoZEdsMlpWdE9VeTVsZUhCdmJtVnVkRjVPVXk1dFlXNTBhWE56WVM1aWIxbE9VeTVzWlc1bmRHaGFUbE11WTI5dGNHRmpkSUFDVHhBUWZRQUFBQUFBQUFBQUFBQUFBQUFBQUFnVFwvXC9cL1wvXC9cL1wvXC9cL1wvOFFBUW5TR3h3ZEhsb2tZMnhoYzNOdVlXMWxXQ1JqYkdGemMyVnpYeEFhVGxORVpXTnBiV0ZzVG5WdFltVnlVR3hoWTJWb2IyeGtaWEtsSHlBaElpTmZFQnBPVTBSbFkybHRZV3hPZFcxaVpYSlFiR0ZqWldodmJHUmxjbDhRRDA1VFJHVmphVzFoYkU1MWJXSmxjbGhPVTA1MWJXSmxjbGRPVTFaaGJIVmxXRTVUVDJKcVpXTjBBQWdBRVFBYUFDUUFLUUF5QURjQVNRQk1BRkVBVXdCWEFGMEFiQUJ6QUg4QWl3Q1hBS1lBc0FDN0FMMEEwQURSQU5vQTNBRGRBT0lBN1FEMkFSTUJHUUUyQVVnQlVRRlpBQUFBQUFBQUFnRUFBQUFBQUFBQUpBQUFBQUFBQUFBQUFBQUFBQUFBQVdJPSIsInN1YnNjcmliZXJJRCI6ImZlZWQiLCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3QiOiJkZWFkIiwiaXNOZXdTdWJzY3JpcHRpb24iOnRydWUsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6MCwibGFiZWwiOiJTdWJzY3JpcHRpb25SZWNlaXB0Q3JlZGVudGFpbFJlZGVtcHRpb24iLCJzdGF0dXMiOjMsInVuaXF1ZUlkIjoiRkNCRDNGOEQtRjIzRi00Nzg0LTlGRTQtMEQ5MkJGQUNDMjhGIiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJkYSBib29wIiwicmVjb3JkVHlwZSI6NzF9LCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3RDb250ZXh0IjoiYmVlZiIsInJlY2VpcHRDcmVkZW50aWFsUHJlc2VudGF0aW9uIjoiYmFkZSIsImJvb3N0UGF5bWVudEludGVudElEIjoiZGUiLCJwYXltZW50UHJvY2Vzc29yIjoiYmFuayIsImlzQm9vc3QiOnRydWV9")!
        ),
        (
            ReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "not svb",
                paymentMethod: nil,
                receiptCredentialRequestContext: Data(base64Encoded: "feeb")!,
                receiptCredentialRequest: Data(base64Encoded: "aded")!,
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
                exclusiveProcessIdentifier: "batman!",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(base64Encoded: "eyJzdWJzY3JpYmVySUQiOiJkZWVmIiwiaXNOZXdTdWJzY3JpcHRpb24iOnRydWUsInNob3VsZFN1cHByZXNzUGF5bWVudEFscmVhZHlSZWRlZW1lZCI6ZmFsc2UsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6MCwibGFiZWwiOiJTdWJzY3JpcHRpb25SZWNlaXB0Q3JlZGVudGFpbFJlZGVtcHRpb24iLCJzdGF0dXMiOjMsInVuaXF1ZUlkIjoiQkNGRUQ5NUMtNTU1MC00MkJELThGMEMtNjlBRTU0NTlGQzhBIiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJiYXRtYW4hIiwicmVjb3JkVHlwZSI6NzF9LCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3RDb250ZXh0IjoiZmVlYiIsInBheW1lbnRQcm9jZXNzb3IiOiJub3Qgc3ZiIiwidGFyZ2V0U3Vic2NyaXB0aW9uTGV2ZWwiOjEyLCJwcmlvclN1YnNjcmlwdGlvbkxldmVsIjo0LCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3QiOiJhZGVkIiwiaXNCb29zdCI6dHJ1ZSwiYm9vc3RQYXltZW50SW50ZW50SUQiOiJuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSJ9")!
        )
    ]

    func validate(against: ReceiptCredentialRedemptionJobRecord) throws {
        guard
            paymentProcessor == against.paymentProcessor,
            receiptCredentialRequestContext == against.receiptCredentialRequestContext,
            receiptCredentialRequest == against.receiptCredentialRequest,
            receiptCredentialPresentation == against.receiptCredentialPresentation,
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
    static let constants: [(SendGiftBadgeJobRecord, base64JsonData: Data)] = [
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
                exclusiveProcessIdentifier: "carp",
                failureCount: 9,
                status: .ready
            ),
            Data(base64Encoded: "eyJwYXlwYWxQYXltZW50VG9rZW4iOiJmbG9ycCIsInRocmVhZElkIjoicGF1bCIsInBheW1lbnRJbnRlbnRDbGllbnRTZWNyZXQiOiJzZWNyZXQiLCJhbW91bnQiOiJZbkJzYVhOME1ERFVBUUlEQkFVR0J3cFlKSFpsY25OcGIyNVpKR0Z5WTJocGRtVnlWQ1IwYjNCWUpHOWlhbVZqZEhNU0FBR0dvRjhRRDA1VFMyVjVaV1JCY21Ob2FYWmxjdEVJQ1ZSeWIyOTBnQUdqQ3d3YVZTUnVkV3hzMXcwT0R4QVJFaE1VRlJZWEdCZ1pWaVJqYkdGemMxdE9VeTV0WVc1MGFYTnpZVnRPVXk1dVpXZGhkR2wyWlZ0T1V5NWxlSEJ2Ym1WdWRGNU9VeTV0WVc1MGFYTnpZUzVpYjFsT1V5NXNaVzVuZEdoYVRsTXVZMjl0Y0dGamRJQUNUeEFRZmdBQUFBQUFBQUFBQUFBQUFBQUFBQWdUXC9cL1wvXC9cL1wvXC9cL1wvXC84UUFRblNHeHdkSGxva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelh4QWFUbE5FWldOcGJXRnNUblZ0WW1WeVVHeGhZMlZvYjJ4a1pYS2xIeUFoSWlOZkVCcE9VMFJsWTJsdFlXeE9kVzFpWlhKUWJHRmpaV2h2YkdSbGNsOFFEMDVUUkdWamFXMWhiRTUxYldKbGNsaE9VMDUxYldKbGNsZE9VMVpoYkhWbFdFNVRUMkpxWldOMEFBZ0FFUUFhQUNRQUtRQXlBRGNBU1FCTUFGRUFVd0JYQUYwQWJBQnpBSDhBaXdDWEFLWUFzQUM3QUwwQTBBRFJBTm9BM0FEZEFPSUE3UUQyQVJNQkdRRTJBVWdCVVFGWkFBQUFBQUFBQWdFQUFBQUFBQUFBSkFBQUFBQUFBQUFBQUFBQUFBQUFBV0k9IiwicmVjZWlwdENyZWRlbnRhaWxSZXF1ZXN0IjoiZGVhZCIsInBheW1lbnRNZXRob2RJZCI6ImNhcnAiLCJtZXNzYWdlVGV4dCI6ImJsYXJwIiwicGF5cGFsUGF5ZXJJZCI6ImJvcnAiLCJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjksImxhYmVsIjoiU2VuZEdpZnRCYWRnZSIsInN0YXR1cyI6MSwidW5pcXVlSWQiOiJFMzlFODRDRS1DQzYxLTRFMUYtOTVERC04MDlCQTIwRUEwQUMiLCJleGNsdXNpdmVQcm9jZXNzSWRlbnRpZmllciI6ImNhcnAiLCJyZWNvcmRUeXBlIjo3M30sImJvb3N0UGF5bWVudEludGVudElEIjoieWFycCIsInJlY2VpcHRDcmVkZW50YWlsUmVxdWVzdENvbnRleHQiOiJiZWVmIiwicGF5cGFsUGF5bWVudElkIjoiZ29ycCIsInBheW1lbnRQcm9jZXNzb3IiOiJtb25leSIsImN1cnJlbmN5Q29kZSI6Inpob29wIn0=")!
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
                exclusiveProcessIdentifier: "carp",
                failureCount: 9,
                status: .ready
            ),
            Data(base64Encoded: "eyJhbW91bnQiOiJZbkJzYVhOME1ERFVBUUlEQkFVR0J3cFlKSFpsY25OcGIyNVpKR0Z5WTJocGRtVnlWQ1IwYjNCWUpHOWlhbVZqZEhNU0FBR0dvRjhRRDA1VFMyVjVaV1JCY21Ob2FYWmxjdEVJQ1ZSeWIyOTBnQUdqQ3d3YVZTUnVkV3hzMXcwT0R4QVJFaE1VRlJZWEdCZ1pWaVJqYkdGemMxdE9VeTV0WVc1MGFYTnpZVnRPVXk1dVpXZGhkR2wyWlZ0T1V5NWxlSEJ2Ym1WdWRGNU9VeTV0WVc1MGFYTnpZUzVpYjFsT1V5NXNaVzVuZEdoYVRsTXVZMjl0Y0dGamRJQUNUeEFRZmdBQUFBQUFBQUFBQUFBQUFBQUFBQWdUXC9cL1wvXC9cL1wvXC9cL1wvXC84UUFRblNHeHdkSGxva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelh4QWFUbE5FWldOcGJXRnNUblZ0WW1WeVVHeGhZMlZvYjJ4a1pYS2xIeUFoSWlOZkVCcE9VMFJsWTJsdFlXeE9kVzFpWlhKUWJHRmpaV2h2YkdSbGNsOFFEMDVUUkdWamFXMWhiRTUxYldKbGNsaE9VMDUxYldKbGNsZE9VMVpoYkhWbFdFNVRUMkpxWldOMEFBZ0FFUUFhQUNRQUtRQXlBRGNBU1FCTUFGRUFVd0JYQUYwQWJBQnpBSDhBaXdDWEFLWUFzQUM3QUwwQTBBRFJBTm9BM0FEZEFPSUE3UUQyQVJNQkdRRTJBVWdCVVFGWkFBQUFBQUFBQWdFQUFBQUFBQUFBSkFBQUFBQUFBQUFBQUFBQUFBQUFBV0k9Iiwic3VwZXIiOnsiZmFpbHVyZUNvdW50Ijo5LCJsYWJlbCI6IlNlbmRHaWZ0QmFkZ2UiLCJzdGF0dXMiOjEsInVuaXF1ZUlkIjoiQTM4NjVENjYtQzA3OC00RkRGLTg1NTctODk4NTlEQkE4RjA3IiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJjYXJwIiwicmVjb3JkVHlwZSI6NzN9LCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3RDb250ZXh0IjoiYmVlZiIsInBheW1lbnRQcm9jZXNzb3IiOiJtb25leSIsImN1cnJlbmN5Q29kZSI6Inpob29wIiwibWVzc2FnZVRleHQiOiJibGFycCIsInJlY2VpcHRDcmVkZW50YWlsUmVxdWVzdCI6ImRlYWQiLCJ0aHJlYWRJZCI6InBhdWwifQ==")!
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
    static let constants: [(SessionResetJobRecord, base64JsonData: Data)] = [
        (
            SessionResetJobRecord(
                contactThreadId: "this",
                exclusiveProcessIdentifier: "the way",
                failureCount: 14,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjE0LCJsYWJlbCI6IlNlc3Npb25SZXNldCIsInN0YXR1cyI6MSwidW5pcXVlSWQiOiJFQjg3RDJEQy05Mjg5LTQ1NUQtQjdGQy0wOEVDQTRDNzMxQ0YiLCJleGNsdXNpdmVQcm9jZXNzSWRlbnRpZmllciI6InRoZSB3YXkiLCJyZWNvcmRUeXBlIjo1Mn0sImNvbnRhY3RUaHJlYWRJZCI6InRoaXMifQ==")!
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
