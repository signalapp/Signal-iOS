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
        case .tsAttachmentMultisend: return TSAttachmentMultisendJobRecord.self
        case .incomingContactSync: return IncomingContactSyncJobRecord.self
        case .legacyMessageDecrypt: return LegacyMessageDecryptJobRecord.self
        case .localUserLeaveGroup: return LocalUserLeaveGroupJobRecord.self
        case .messageSender: return MessageSenderJobRecord.self
        case .receiptCredentialRedemption: return ReceiptCredentialRedemptionJobRecord.self
        case .sendGiftBadge: return SendGiftBadgeJobRecord.self
        case .sessionReset: return SessionResetJobRecord.self
        case .callRecordDeleteAll: return CallRecordDeleteAllJobRecord.self
        case .bulkDeleteInteractionJobRecord: return BulkDeleteInteractionJobRecord.self
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

extension TSAttachmentMultisendJobRecord: ValidatableModel {
    static let constants: [(TSAttachmentMultisendJobRecord, base64JsonData: Data)] = [
        (
            TSAttachmentMultisendJobRecord(
                attachmentIdMap: ["once": ["upon", "a"]],
                // The encoded object below has a non-story message, which is invalid in the real app.
                storyMessagesToSend: [],
                exclusiveProcessIdentifier: nil,
                failureCount: 3,
                status: .running
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjMsImxhYmVsIjoiQnJvYWRjYXN0TWVkaWFNZXNzYWdlIiwic3RhdHVzIjoyLCJ1bmlxdWVJZCI6IkY1QjMzODBDLUI0REItNDVERS1CQjA3LUNDNkJDQUU5N0ZEQiIsInJlY29yZFR5cGUiOjU4fSwiYXR0YWNobWVudElkTWFwIjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHb0N3d1ZGaHNjSFNOVkpHNTFiR3pURFE0UEVCSVVWMDVUTG10bGVYTmFUbE11YjJKcVpXTjBjMVlrWTJ4aGMzT2hFWUFDb1JPQUE0QUhWRzl1WTJYU0RnOFhHcUlZR1lBRWdBV0FCbFIxY0c5dVVXSFNIaDhnSVZva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelYwNVRRWEp5WVhtaUlDSllUbE5QWW1wbFkzVFNIaDhrSlZ4T1UwUnBZM1JwYjI1aGNubWlKaUpjVGxORWFXTjBhVzl1WVhKNUNCRWFKQ2t5TjBsTVVWTmNZbWx4ZklPRmg0bUxqWktYbXB5ZW9LV25yTGZBeU12VTJlYnBBQUFBQUFBQUFRRUFBQUFBQUFBQUp3QUFBQUFBQUFBQUFBQUFBQUFBQVBZPSIsInVuc2F2ZWRNZXNzYWdlc1RvU2VuZCI6IlluQnNhWE4wTUREVUFRSURCQVVHQndwWUpIWmxjbk5wYjI1WkpHRnlZMmhwZG1WeVZDUjBiM0JZSkc5aWFtVmpkSE1TQUFHR29GOFFEMDVUUzJWNVpXUkJjbU5vYVhabGN0RUlDVlJ5YjI5MGdBR3FDd3dTUmtkSVNVcExWMVVrYm5Wc2JOSU5EZzhSV2s1VExtOWlhbVZqZEhOV0pHTnNZWE56b1JDQUFvQUozeEFhRXhRVkZnNFhHQmthR3h3ZEhoOGdJU0lqSkNVbUp5Z3BLaXNzTFMwc01DMHNNeTBzTFN3c0xDd3RMU3d0TEN4QlFpd3RMVjhRRTNKbFkyVnBkbVZrUVhSVWFXMWxjM1JoYlhCZkVCSnBjMVpwWlhkUGJtTmxRMjl0Y0d4bGRHVmZFQnh6ZEc5eVpXUlRhRzkxYkdSVGRHRnlkRVY0Y0dseVpWUnBiV1Z5WHhBUFpYaHdhWEpsVTNSaGNuUmxaRUYwWHhBUmFYTldhV1YzVDI1alpVMWxjM05oWjJWZkVBOU5WRXhOYjJSbGJGWmxjbk5wYjI1ZWRXNXBjWFZsVkdoeVpXRmtTV1JmRUJWb1lYTk1aV2RoWTNsTlpYTnpZV2RsVTNSaGRHVldjMjl5ZEVsa1h4QVNhWE5HY205dFRHbHVhMlZrUkdWMmFXTmxYeEFjYjNWMFoyOXBibWROWlhOellXZGxVMk5vWlcxaFZtVnljMmx2Ymw4UUVHVjRjR2x5WlhOSmJsTmxZMjl1WkhOZkVCQm5jbTkxY0UxbGRHRk5aWE56WVdkbFh4QVNiR1ZuWVdONVRXVnpjMkZuWlZOMFlYUmxYeEFTYkdWbllXTjVWMkZ6UkdWc2FYWmxjbVZrWG1selZtOXBZMlZOWlhOellXZGxXV1Y0Y0dseVpYTkJkRjhRRVdselIzSnZkWEJUZEc5eWVWSmxjR3g1WFhOamFHVnRZVlpsY25OcGIyNVpaV1JwZEZOMFlYUmxXWFJwYldWemRHRnRjRmgxYm1seGRXVkpaRjhRRW5OMGIzSmxaRTFsYzNOaFoyVlRkR0YwWlY4UUVuZGhjMUpsYlc5MFpXeDVSR1ZzWlhSbFpGOFFFMmhoYzFONWJtTmxaRlJ5WVc1elkzSnBjSFNBQTRBRWdBU0FBNEFJZ0FTQUE0QUZnQVNBQTRBRWdBT0FBNEFEZ0FPQUJJQUVnQU9BQklBRGdBT0FCNEFHZ0FPQUJJQUVFQUFJVzJsdUlHRWdaMkZzWVhoNVZIUnBiV1VUQUFBQmpEYzAxV1hTVEUxT1Qxb2tZMnhoYzNOdVlXMWxXQ1JqYkdGemMyVnpYeEFSVkZOUGRYUm5iMmx1WjAxbGMzTmhaMlduVUZGU1UxUlZWbDhRRVZSVFQzVjBaMjlwYm1kTlpYTnpZV2RsV1ZSVFRXVnpjMkZuWlYxVVUwbHVkR1Z5WVdOMGFXOXVXVUpoYzJWTmIyUmxiRjhRRTFSVFdXRndSR0YwWVdKaGMyVlBZbXBsWTNSWVRWUk1UVzlrWld4WVRsTlBZbXBsWTNUU1RFMVlXVmRPVTBGeWNtRjVvbGhXQUFnQUVRQWFBQ1FBS1FBeUFEY0FTUUJNQUZFQVV3QmVBR1FBYVFCMEFIc0FmUUJcL0FJRUF1QURPQU9NQkFnRVVBU2dCT2dGSkFXRUJhQUY5QVp3QnJ3SENBZGNCN0FIN0FnVUNHUUluQWpFQ093SkVBbGtDYmdLRUFvWUNpQUtLQW93Q2pnS1FBcElDbEFLV0FwZ0NtZ0tjQXA0Q29BS2lBcVFDcGdLb0Fxb0NyQUt1QXJBQ3NnSzBBcllDdUFLNkFyc0N4d0xNQXRVQzJnTGxBdTREQWdNS0F4NERLQU0yQTBBRFZnTmZBMmdEYlFOMUFBQUFBQUFBQWdFQUFBQUFBQUFBV2dBQUFBQUFBQUFBQUFBQUFBQUFBM2c9In0=")!
        ),
        (
            TSAttachmentMultisendJobRecord(
                attachmentIdMap: ["once": ["upon", "a"]],
                storyMessagesToSend: nil,
                exclusiveProcessIdentifier: nil,
                failureCount: 3,
                status: .running
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjMsImxhYmVsIjoiQnJvYWRjYXN0TWVkaWFNZXNzYWdlIiwic3RhdHVzIjoyLCJ1bmlxdWVJZCI6IjNFQjkwNDM1LTkwNEEtNDZEQS05NTFELUFGNTc3QjM4QURENyIsInJlY29yZFR5cGUiOjU4fSwiYXR0YWNobWVudElkTWFwIjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHb0N3d1ZGaHNjSFNOVkpHNTFiR3pURFE0UEVCSVVWMDVUTG10bGVYTmFUbE11YjJKcVpXTjBjMVlrWTJ4aGMzT2hFWUFDb1JPQUE0QUhWRzl1WTJYU0RnOFhHcUlZR1lBRWdBV0FCbFIxY0c5dVVXSFNIaDhnSVZva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelYwNVRRWEp5WVhtaUlDSllUbE5QWW1wbFkzVFNIaDhrSlZ4T1UwUnBZM1JwYjI1aGNubWlKaUpjVGxORWFXTjBhVzl1WVhKNUNCRWFKQ2t5TjBsTVVWTmNZbWx4ZklPRmg0bUxqWktYbXB5ZW9LV25yTGZBeU12VTJlYnBBQUFBQUFBQUFRRUFBQUFBQUFBQUp3QUFBQUFBQUFBQUFBQUFBQUFBQVBZPSJ9")!
        )
    ]

    func validate(against: TSAttachmentMultisendJobRecord) throws {
        guard
            attachmentIdMap == against.attachmentIdMap,
            storyMessagesToSend?.count == against.storyMessagesToSend?.count,
            storyMessagesToSend?.first?.uniqueId == against.storyMessagesToSend?.first?.uniqueId
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

extension IncomingContactSyncJobRecord: ValidatableModel {
    static let constants: [(IncomingContactSyncJobRecord, base64JsonData: Data)] = [
        (
            IncomingContactSyncJobRecord.legacy(
                legacyAttachmentId: "darth revan",
                isCompleteContactSync: true,
                exclusiveProcessIdentifier: "star wars character",
                failureCount: 12,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjEyLCJsYWJlbCI6IkluY29taW5nQ29udGFjdFN5bmMiLCJzdGF0dXMiOjEsInVuaXF1ZUlkIjoiRkYzNzUzQjMtQjFGRC00QjRBLTk2QzMtMjM5OEVCMTIwMTM2IiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJzdGFyIHdhcnMgY2hhcmFjdGVyIiwicmVjb3JkVHlwZSI6NjF9LCJpc0NvbXBsZXRlQ29udGFjdFN5bmMiOnRydWUsImF0dGFjaG1lbnRJZCI6ImRhcnRoIHJldmFuIn0=")!
        ),
        (
            IncomingContactSyncJobRecord.legacy(
                legacyAttachmentId: nil,
                isCompleteContactSync: false,
                exclusiveProcessIdentifier: "star wars villain",
                failureCount: 6,
                status: .permanentlyFailed
            ),
            Data(base64Encoded: "eyJpc0NvbXBsZXRlQ29udGFjdFN5bmMiOmZhbHNlLCJzdXBlciI6eyJ1bmlxdWVJZCI6IkIxMzQxNDU5LTNCQTMtNEFBNy04NUZGLURFQ0YxMDlBNzRFQSIsImV4Y2x1c2l2ZVByb2Nlc3NJZGVudGlmaWVyIjoic3RhciB3YXJzIHZpbGxhaW4iLCJmYWlsdXJlQ291bnQiOjYsInJlY29yZFR5cGUiOjYxLCJzdGF0dXMiOjMsImxhYmVsIjoiSW5jb21pbmdDb250YWN0U3luYyJ9fQ==")!
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
            Data(base64Encoded: "eyJJQ1NKUl9kaWdlc3QiOiIyOTFiblFpT2pZc0luSmxZMjl5WkZSNWNHVWlPIiwiSUNTSlJfcGxhaW50ZXh0TGVuZ3RoIjo1NSwiSUNTSlJfY2RuS2V5IjoiaGVsbG8iLCJzdXBlciI6eyJzdGF0dXMiOjEsImZhaWx1cmVDb3VudCI6MCwibGFiZWwiOiJJbmNvbWluZ0NvbnRhY3RTeW5jIiwidW5pcXVlSWQiOiI4OTRFQUM1RS05MThCLTQzNEMtQTdDRS1DMjRCQjhGNDc5MzIiLCJyZWNvcmRUeXBlIjo2MX0sIklDU0pSX2Nkbk51bWJlciI6MywiSUNTSlJfZW5jcnlwdGlvbktleSI6Im1NaU9tWmhiSE5sTENKemRYQmxjaUk2ZXlKMWIiLCJpc0NvbXBsZXRlQ29udGFjdFN5bmMiOnRydWV9")!
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
        case let (.legacy(lhsId), .legacy(rhsId)):
            guard
                lhsId == rhsId
            else {
                throw ValidatableModelError.failedToValidate
            }
        case let (.transient(lhsInfo), .transient(rhsInfo)):
            guard
                lhsInfo == rhsInfo
            else {
                throw ValidatableModelError.failedToValidate
            }
        case (.invalid, _), (.legacy, _), (.transient, _):
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
                threadId: "6A860318-BC21-46BC-B1B2-695ED5D6D8A2",
                messageType: .persisted(messageId: "1668418F-4913-4852-8B01-4E5EF8938B33", useMediaQueue: true),
                removeMessageAfterSending: false,
                isHighPriority: true,
                exclusiveProcessIdentifier: nil,
                failureCount: UInt(Int.max),
                status: .unknown
            ),
            Data(base64Encoded: "eyJtZXNzYWdlSWQiOiIxNjY4NDE4Ri00OTEzLTQ4NTItOEIwMS00RTVFRjg5MzhCMzMiLCJpc01lZGlhTWVzc2FnZSI6dHJ1ZSwic3VwZXIiOnsiZmFpbHVyZUNvdW50Ijo5MjIzMzcyMDM2ODU0Nzc1ODA3LCJzdGF0dXMiOjAsImxhYmVsIjoiTWVzc2FnZVNlbmRlciIsInVuaXF1ZUlkIjoiNzY5NUUyM0ItNDRDQi00QTVBLTkwMTItOTE1Q0IzRTMzMUMxIiwicmVjb3JkVHlwZSI6MzV9LCJyZW1vdmVNZXNzYWdlQWZ0ZXJTZW5kaW5nIjpmYWxzZSwiaXNIaWdoUHJpb3JpdHkiOnRydWUsInRocmVhZElkIjoiNkE4NjAzMTgtQkMyMS00NkJDLUIxQjItNjk1RUQ1RDZEOEEyIn0=")!
        ),
        (
            MessageSenderJobRecord(
                threadId: nil,
                messageType: .none,
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

extension CallRecordDeleteAllJobRecord: ValidatableModel {
    static let constants: [(CallRecordDeleteAllJobRecord, base64JsonData: Data)] = [
        (
            CallRecordDeleteAllJobRecord(
                sendDeleteAllSyncMessage: true,
                deleteAllBeforeCallId: nil,
                deleteAllBeforeConversationId: nil,
                deleteAllBeforeTimestamp: 1234,
                exclusiveProcessIdentifier: "blorp",
                failureCount: 19,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJsYWJlbCI6IkNhbGxSZWNvcmREZWxldGVBbGwiLCJ1bmlxdWVJZCI6IjM5ODlDQ0E0LThDMUQtNDNGQy05NUMwLUMzRjU5ODUwQUUyRiIsImV4Y2x1c2l2ZVByb2Nlc3NJZGVudGlmaWVyIjoiYmxvcnAiLCJmYWlsdXJlQ291bnQiOjE5LCJyZWNvcmRUeXBlIjoxMDAsInN0YXR1cyI6MX0sIkNSREFKUl9zZW5kRGVsZXRlQWxsU3luY01lc3NhZ2UiOnRydWUsIkNSREFKUl9kZWxldGVBbGxCZWZvcmVUaW1lc3RhbXAiOjEyMzR9")!
        ),
        (
            CallRecordDeleteAllJobRecord(
                sendDeleteAllSyncMessage: true,
                deleteAllBeforeCallId: 6789,
                deleteAllBeforeConversationId: Aci.constantForTesting("E84A2412-09CB-4EFB-9B1D-3BEB65C14481").serviceIdBinary.asData,
                deleteAllBeforeTimestamp: 1234,
                exclusiveProcessIdentifier: "blorp",
                failureCount: 19,
                status: .ready
            ),
            Data(base64Encoded: "eyJDUkRBSlJfZGVsZXRlQWxsQmVmb3JlQ29udmVyc2F0aW9uSWQiOiI2RW9rRWduTFR2dWJIVHZyWmNGRWdRPT0iLCJDUkRBSlJfZGVsZXRlQWxsQmVmb3JlVGltZXN0YW1wIjoxMjM0LCJDUkRBSlJfZGVsZXRlQWxsQmVmb3JlQ2FsbElkIjoiNjc4OSIsInN1cGVyIjp7ImxhYmVsIjoiQ2FsbFJlY29yZERlbGV0ZUFsbCIsInN0YXR1cyI6MSwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJibG9ycCIsInJlY29yZFR5cGUiOjEwMCwiZmFpbHVyZUNvdW50IjoxOSwidW5pcXVlSWQiOiJDNTg1MjdCNS1DNkM4LTRDQ0ItQjhGRS1BQTk2NkE3N0U4RjAifSwiQ1JEQUpSX3NlbmREZWxldGVBbGxTeW5jTWVzc2FnZSI6dHJ1ZX0=")!
        ),
        (
            CallRecordDeleteAllJobRecord(
                sendDeleteAllSyncMessage: true,
                deleteAllBeforeCallId: 6789,
                deleteAllBeforeConversationId: Data(repeating: 5, count: 32),
                deleteAllBeforeTimestamp: 1234,
                exclusiveProcessIdentifier: "blorp",
                failureCount: 19,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjE5LCJyZWNvcmRUeXBlIjoxMDAsImxhYmVsIjoiQ2FsbFJlY29yZERlbGV0ZUFsbCIsInVuaXF1ZUlkIjoiOUMyMDc3NzctRkI5Ri00NjNELTlCMzEtMDhBMUIzMUU0QzMzIiwic3RhdHVzIjoxLCJleGNsdXNpdmVQcm9jZXNzSWRlbnRpZmllciI6ImJsb3JwIn0sIkNSREFKUl9zZW5kRGVsZXRlQWxsU3luY01lc3NhZ2UiOnRydWUsIkNSREFKUl9kZWxldGVBbGxCZWZvcmVUaW1lc3RhbXAiOjEyMzQsIkNSREFKUl9kZWxldGVBbGxCZWZvcmVDYWxsSWQiOiI2Nzg5IiwiQ1JEQUpSX2RlbGV0ZUFsbEJlZm9yZUNvbnZlcnNhdGlvbklkIjoiQlFVRkJRVUZCUVVGQlFVRkJRVUZCUVVGQlFVRkJRVUZCUVVGQlFVRkJRVT0ifQ==")!
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
    static let constants: [(BulkDeleteInteractionJobRecord, base64JsonData: Data)] = [
        (
            BulkDeleteInteractionJobRecord(
                anchorMessageRowId: 12,
                fullThreadDeletionAnchorMessageRowId: 42,
                threadUniqueId: "8279D1D7-EA6F-4D4E-A652-ADBF03DDDF14"
            ),
            Data(base64Encoded: "eyJCRElKUl9hbmNob3JNZXNzYWdlUm93SWQiOjEyLCJCRElKUl90aHJlYWRVbmlxdWVJZCI6IjgyNzlEMUQ3LUVBNkYtNEQ0RS1BNjUyLUFEQkYwM0REREYxNCIsIkJESUpSX2Z1bGxUaHJlYWREZWxldGlvbkFuY2hvck1lc3NhZ2VSb3dJZCI6NDIsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6MCwic3RhdHVzIjoxLCJsYWJlbCI6IkJ1bGtEZWxldGVJbnRlcmFjdGlvbiIsInJlY29yZFR5cGUiOjEwMSwidW5pcXVlSWQiOiJFMDFDRDZGMC1BM0IyLTRBQzYtODAxNC05REFGQkMzNkVCNjMifX0=")!
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
