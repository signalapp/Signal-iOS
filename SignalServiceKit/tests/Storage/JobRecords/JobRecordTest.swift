//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class JobRecordTest: XCTestCase {
    private let inMemoryDatabase = InMemoryDatabase()

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
        case .subscriptionReceiptCredentialRedemption: return SubscriptionReceiptCredentialRedemptionJobRecord.self
        case .sendGiftBadge: return SendGiftBadgeJobRecord.self
        case .sessionReset: return SessionResetJobRecord.self
        }
    }

    // MARK: - Round trip

    func testRoundTrip() {
        func roundTripValidateConstant<T: JobRecord & ValidatableModel>(constant: T, index: Int) {
            inMemoryDatabase.insert(record: constant)

            let deserialized: T? = inMemoryDatabase.fetchExactlyOne(modelType: T.self)

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

            inMemoryDatabase.remove(model: deserialized)
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
                label: "far far away",
                exclusiveProcessIdentifier: nil,
                failureCount: 3,
                status: .running
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjMsImxhYmVsIjoiZmFyIGZhciBhd2F5Iiwic3RhdHVzIjoyLCJ1bmlxdWVJZCI6IkY0MzY2OTlBLTE5QTMtNDU1OC1CNzEyLUQ0MUYyNUM3RThBMiIsInJlY29yZFR5cGUiOjU4fSwiYXR0YWNobWVudElkTWFwIjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHb0N3d1ZGaHNjSFNOVkpHNTFiR3pURFE0UEVCSVVWMDVUTG10bGVYTmFUbE11YjJKcVpXTjBjMVlrWTJ4aGMzT2hFWUFDb1JPQUE0QUhWRzl1WTJYU0RnOFhHcUlZR1lBRWdBV0FCbFIxY0c5dVVXSFNIaDhnSVZva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelYwNVRRWEp5WVhtaUlDSllUbE5QWW1wbFkzVFNIaDhrSlZ4T1UwUnBZM1JwYjI1aGNubWlKaUpjVGxORWFXTjBhVzl1WVhKNUNCRWFKQ2t5TjBsTVVWTmNZbWx4ZklPRmg0bUxqWktYbXB5ZW9LV25yTGZBeU12VTJlYnBBQUFBQUFBQUFRRUFBQUFBQUFBQUp3QUFBQUFBQUFBQUFBQUFBQUFBQVBZPSIsInVuc2F2ZWRNZXNzYWdlc1RvU2VuZCI6IlluQnNhWE4wTUREVUFRSURCQVVHQndwWUpIWmxjbk5wYjI1WkpHRnlZMmhwZG1WeVZDUjBiM0JZSkc5aWFtVmpkSE1TQUFHR29GOFFEMDVUUzJWNVpXUkJjbU5vYVhabGN0RUlDVlJ5YjI5MGdBR3FDd3dTUkVWR1IwaEpWVlVrYm5Wc2JOSU5EZzhSV2s1VExtOWlhbVZqZEhOV0pHTnNZWE56b1JDQUFvQUozeEFaRXhRVkZnNFhHQmthR3h3ZEhoOGdJU0lqSkNVbUp5Z3BLaXNzTENzdkxDc3lMQ3NzS3lzckt5d3NLeXdyUDBBckxDeGZFQk55WldObGFYWmxaRUYwVkdsdFpYTjBZVzF3WHhBU2FYTldhV1YzVDI1alpVTnZiWEJzWlhSbFh4QWNjM1J2Y21Wa1UyaHZkV3hrVTNSaGNuUkZlSEJwY21WVWFXMWxjbDhRRDJWNGNHbHlaVk4wWVhKMFpXUkJkRjhRRVdselZtbGxkMDl1WTJWTlpYTnpZV2RsWHhBUFRWUk1UVzlrWld4V1pYSnphVzl1WG5WdWFYRjFaVlJvY21WaFpFbGtYeEFWYUdGelRHVm5ZV041VFdWemMyRm5aVk4wWVhSbFZuTnZjblJKWkY4UUVtbHpSbkp2YlV4cGJtdGxaRVJsZG1salpWOFFIRzkxZEdkdmFXNW5UV1Z6YzJGblpWTmphR1Z0WVZabGNuTnBiMjVmRUJCbGVIQnBjbVZ6U1c1VFpXTnZibVJ6WHhBUVozSnZkWEJOWlhSaFRXVnpjMkZuWlY4UUVteGxaMkZqZVUxbGMzTmhaMlZUZEdGMFpWOFFFbXhsWjJGamVWZGhjMFJsYkdsMlpYSmxaRjVwYzFadmFXTmxUV1Z6YzJGblpWbGxlSEJwY21WelFYUmZFQkZwYzBkeWIzVndVM1J2Y25sU1pYQnNlVjF6WTJobGJXRldaWEp6YVc5dVdYUnBiV1Z6ZEdGdGNGaDFibWx4ZFdWSlpGOFFFbk4wYjNKbFpFMWxjM05oWjJWVGRHRjBaVjhRRW5kaGMxSmxiVzkwWld4NVJHVnNaWFJsWkY4UUUyaGhjMU41Ym1ObFpGUnlZVzV6WTNKcGNIU0FBNEFFZ0FTQUE0QUlnQVNBQTRBRmdBU0FBNEFFZ0FPQUE0QURnQU9BQklBRWdBT0FCSUFEZ0FlQUJvQURnQVNBQkJBQUNGdHBiaUJoSUdkaGJHRjRlVlIwYVcxbEV3QUFBWWQzcThsbDBrcExURTFhSkdOc1lYTnpibUZ0WlZna1kyeGhjM05sYzE4UUVWUlRUM1YwWjI5cGJtZE5aWE56WVdkbHAwNVBVRkZTVTFSZkVCRlVVMDkxZEdkdmFXNW5UV1Z6YzJGblpWbFVVMDFsYzNOaFoyVmRWRk5KYm5SbGNtRmpkR2x2YmxsQ1lYTmxUVzlrWld4ZkVCTlVVMWxoY0VSaGRHRmlZWE5sVDJKcVpXTjBXRTFVVEUxdlpHVnNXRTVUVDJKcVpXTjAwa3BMVmxkWFRsTkJjbkpoZWFKV1ZBQUlBQkVBR2dBa0FDa0FNZ0EzQUVrQVRBQlJBRk1BWGdCa0FHa0FkQUI3QUgwQWZ3Q0JBTFlBekFEaEFRQUJFZ0VtQVRnQlJ3RmZBV1lCZXdHYUFhMEJ3QUhWQWVvQitRSURBaGNDSlFJdkFqZ0NUUUppQW5nQ2VnSjhBbjRDZ0FLQ0FvUUNoZ0tJQW9vQ2pBS09BcEFDa2dLVUFwWUNtQUthQXB3Q25nS2dBcUlDcEFLbUFxZ0NxZ0tzQXEwQ3VRSytBc2NDekFMWEF1QUM5QUw4QXhBREdnTW9BeklEU0FOUkExb0RYd05uQUFBQUFBQUFBZ0VBQUFBQUFBQUFXQUFBQUFBQUFBQUFBQUFBQUFBQUEybz0ifQ==")!
        ),
        (
            BroadcastMediaMessageJobRecord(
                attachmentIdMap: ["once": ["upon", "a"]],
                unsavedMessagesToSend: nil,
                label: "far far away",
                exclusiveProcessIdentifier: nil,
                failureCount: 3,
                status: .running
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjMsImxhYmVsIjoiZmFyIGZhciBhd2F5Iiwic3RhdHVzIjoyLCJ1bmlxdWVJZCI6IjI3NUFDOTVGLUU3QjAtNDBGNy05MUQ2LTA1MDY3NERBRjk1MSIsInJlY29yZFR5cGUiOjU4fSwiYXR0YWNobWVudElkTWFwIjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHb0N3d1ZGaHNjSFNOVkpHNTFiR3pURFE0UEVCSVVWMDVUTG10bGVYTmFUbE11YjJKcVpXTjBjMVlrWTJ4aGMzT2hFWUFDb1JPQUE0QUhWRzl1WTJYU0RnOFhHcUlZR1lBRWdBV0FCbFIxY0c5dVVXSFNIaDhnSVZva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelYwNVRRWEp5WVhtaUlDSllUbE5QWW1wbFkzVFNIaDhrSlZ4T1UwUnBZM1JwYjI1aGNubWlKaUpjVGxORWFXTjBhVzl1WVhKNUNCRWFKQ2t5TjBsTVVWTmNZbWx4ZklPRmg0bUxqWktYbXB5ZW9LV25yTGZBeU12VTJlYnBBQUFBQUFBQUFRRUFBQUFBQUFBQUp3QUFBQUFBQUFBQUFBQUFBQUFBQVBZPSJ9")!
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
                label: "is the best",
                exclusiveProcessIdentifier: "star wars character",
                failureCount: 12,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjEyLCJsYWJlbCI6ImlzIHRoZSBiZXN0Iiwic3RhdHVzIjoxLCJ1bmlxdWVJZCI6IkYxODI0OThCLTlGQkQtNERGMi1CMUVFLUJEMkFGOUY1MTI3OCIsImV4Y2x1c2l2ZVByb2Nlc3NJZGVudGlmaWVyIjoic3RhciB3YXJzIGNoYXJhY3RlciIsInJlY29yZFR5cGUiOjYxfSwiaXNDb21wbGV0ZUNvbnRhY3RTeW5jIjp0cnVlLCJhdHRhY2htZW50SWQiOiJkYXJ0aCByZXZhbiJ9")!
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
                label: "to you",
                exclusiveProcessIdentifier: "happy birthday TO YOOOU",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjAsImxhYmVsIjoidG8geW91Iiwic3RhdHVzIjozLCJ1bmlxdWVJZCI6IkUzOTVBREZBLURGNzktNDlCNi04RTVDLTk1NTQ0NzMxODAxRCIsImV4Y2x1c2l2ZVByb2Nlc3NJZGVudGlmaWVyIjoiaGFwcHkgYmlydGhkYXkgVE8gWU9PT1UiLCJyZWNvcmRUeXBlIjo2MH0sImF0dGFjaG1lbnRJZCI6ImhhcHB5IGJpcnRoZGF5In0=")!
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
                label: "never gonna",
                exclusiveProcessIdentifier: "give you up",
                failureCount: 0,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjAsImxhYmVsIjoibmV2ZXIgZ29ubmEiLCJzdGF0dXMiOjEsInVuaXF1ZUlkIjoiQzFGMzk4OUQtNTI0MC00QjBDLTk5RUQtMEM3OTEyMDdCMDgwIiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJnaXZlIHlvdSB1cCIsInJlY29yZFR5cGUiOjUzfSwiZW52ZWxvcGVEYXRhIjoiYmVlZiIsInNlcnZlckRlbGl2ZXJ5VGltZXN0YW1wIjoxMn0=")!
        ),
        (
            LegacyMessageDecryptJobRecord(
                envelopeData: nil,
                serverDeliveryTimestamp: 12,
                label: "never gonna",
                exclusiveProcessIdentifier: "give you up",
                failureCount: 0,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjAsImxhYmVsIjoibmV2ZXIgZ29ubmEiLCJzdGF0dXMiOjEsInVuaXF1ZUlkIjoiNDNCRENDMkMtQTM1RC00OTZCLTk5NTgtQ0E0QTA0RkY3MTY4IiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJnaXZlIHlvdSB1cCIsInJlY29yZFR5cGUiOjUzfSwic2VydmVyRGVsaXZlcnlUaW1lc3RhbXAiOjEyfQ==")!
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
                label: "round and round",
                exclusiveProcessIdentifier: "round and round!",
                failureCount: 40000,
                status: .obsolete
            ),
            Data(base64Encoded: "eyJyZXBsYWNlbWVudEFkbWluVXVpZCI6IjAwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMEFBQSIsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6NDAwMDAsImxhYmVsIjoicm91bmQgYW5kIHJvdW5kIiwic3RhdHVzIjo0LCJ1bmlxdWVJZCI6Ijg1M0U2NkNDLTQzNUQtNDY1NS1CRDAxLTRGMDJFMzExM0ZFMiIsImV4Y2x1c2l2ZVByb2Nlc3NJZGVudGlmaWVyIjoicm91bmQgYW5kIHJvdW5kISIsInJlY29yZFR5cGUiOjc0fSwidGhyZWFkSWQiOiJ0aGUgd2hlZWxzIG9uIHRoZSBidXMiLCJ3YWl0Rm9yTWVzc2FnZVByb2Nlc3NpbmciOnRydWV9Cg==")!
        ),
        (
            LocalUserLeaveGroupJobRecord(
                threadId: "the wheels on the bus",
                replacementAdminAci: nil,
                waitForMessageProcessing: true,
                label: "go round and round",
                exclusiveProcessIdentifier: "round and round!",
                failureCount: 40000,
                status: .obsolete
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjQwMDAwLCJsYWJlbCI6ImdvIHJvdW5kIGFuZCByb3VuZCIsInN0YXR1cyI6NCwidW5pcXVlSWQiOiI1NDA0NDI3OS1CQzdBLTQ5RTctQjU2Ri0zMDNDN0ZEQkUzNDIiLCJleGNsdXNpdmVQcm9jZXNzSWRlbnRpZmllciI6InJvdW5kIGFuZCByb3VuZCEiLCJyZWNvcmRUeXBlIjo3NH0sInRocmVhZElkIjoidGhlIHdoZWVscyBvbiB0aGUgYnVzIiwid2FpdEZvck1lc3NhZ2VQcm9jZXNzaW5nIjp0cnVlfQ==")!
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
                label: "problem",
                exclusiveProcessIdentifier: nil,
                failureCount: UInt(Int.max),
                status: .unknown
            ),
            Data(base64Encoded: "eyJtZXNzYWdlSWQiOiJob3VzdG9uIiwidGhyZWFkSWQiOiJ3ZSIsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6OTIyMzM3MjAzNjg1NDc3NTgwNywibGFiZWwiOiJwcm9ibGVtIiwic3RhdHVzIjowLCJ1bmlxdWVJZCI6IjREMjhGNzMzLURFRjQtNDE4MC05NUEwLUQ1NUI0RkYyMTlBMSIsInJlY29yZFR5cGUiOjM1fSwicmVtb3ZlTWVzc2FnZUFmdGVyU2VuZGluZyI6ZmFsc2UsImlzSGlnaFByaW9yaXR5Ijp0cnVlLCJpbnZpc2libGVNZXNzYWdlIjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHb0N3d1wvUUVGQ1EwUlZKRzUxYkd6ZkVCa05EZzhRRVJJVEZCVVdGeGdaR2hzY0hSNGZJQ0VpSXlRbEppY25KaW9uSmkwbkppY21KaVltSnljbUp5WTZPeVluSjE4UUUzSmxZMlZwZG1Wa1FYUlVhVzFsYzNSaGJYQmZFQkpwYzFacFpYZFBibU5sUTI5dGNHeGxkR1ZmRUJ4emRHOXlaV1JUYUc5MWJHUlRkR0Z5ZEVWNGNHbHlaVlJwYldWeVh4QVBaWGh3YVhKbFUzUmhjblJsWkVGMFZpUmpiR0Z6YzE4UUVXbHpWbWxsZDA5dVkyVk5aWE56WVdkbFh4QVBUVlJNVFc5a1pXeFdaWEp6YVc5dVhuVnVhWEYxWlZSb2NtVmhaRWxrWHhBVmFHRnpUR1ZuWVdONVRXVnpjMkZuWlZOMFlYUmxWbk52Y25SSlpGOFFFbWx6Um5KdmJVeHBibXRsWkVSbGRtbGpaVjhRSEc5MWRHZHZhVzVuVFdWemMyRm5aVk5qYUdWdFlWWmxjbk5wYjI1ZkVCQmxlSEJwY21WelNXNVRaV052Ym1Selh4QVFaM0p2ZFhCTlpYUmhUV1Z6YzJGblpWOFFFbXhsWjJGamVVMWxjM05oWjJWVGRHRjBaVjhRRW14bFoyRmplVmRoYzBSbGJHbDJaWEpsWkY1cGMxWnZhV05sVFdWemMyRm5aVmxsZUhCcGNtVnpRWFJmRUJGcGMwZHliM1Z3VTNSdmNubFNaWEJzZVYxelkyaGxiV0ZXWlhKemFXOXVXWFJwYldWemRHRnRjRmgxYm1seGRXVkpaRjhRRW5OMGIzSmxaRTFsYzNOaFoyVlRkR0YwWlY4UUVuZGhjMUpsYlc5MFpXeDVSR1ZzWlhSbFpGOFFFMmhoYzFONWJtTmxaRlJ5WVc1elkzSnBjSFNBQW9BRGdBT0FBb0FIZ0FPQUFvQUVnQU9BQW9BRGdBS0FBb0FDZ0FLQUE0QURnQUtBQTRBQ2dBYUFCWUFDZ0FPQUF4QUFDRkZoVkdoaGRtVVRBQUFCaDNmRWF3alNSVVpIU0Zva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelh4QVJWRk5QZFhSbmIybHVaMDFsYzNOaFoyV25TVXBMVEUxT1QxOFFFVlJUVDNWMFoyOXBibWROWlhOellXZGxXVlJUVFdWemMyRm5aVjFVVTBsdWRHVnlZV04wYVc5dVdVSmhjMlZOYjJSbGJGOFFFMVJUV1dGd1JHRjBZV0poYzJWUFltcGxZM1JZVFZSTVRXOWtaV3hZVGxOUFltcGxZM1FBQ0FBUkFCb0FKQUFwQURJQU53QkpBRXdBVVFCVEFGd0FZZ0NYQUswQXdnRGhBUE1BK2dFT0FTQUJMd0ZIQVU0Qll3R0NBWlVCcUFHOUFkSUI0UUhyQWY4Q0RRSVhBaUFDTlFKS0FtQUNZZ0prQW1ZQ2FBSnFBbXdDYmdKd0FuSUNkQUoyQW5nQ2VnSjhBbjRDZ0FLQ0FvUUNoZ0tJQW9vQ2pBS09BcEFDa2dLVUFwVUNsd0tjQXFVQ3FnSzFBcjRDMGdMYUF1NEMrQU1HQXhBREpnTXZBQUFBQUFBQUFnRUFBQUFBQUFBQVVBQUFBQUFBQUFBQUFBQUFBQUFBQXpnPSIsImlzTWVkaWFNZXNzYWdlIjp0cnVlfQ==")!
        ),
        (
            MessageSenderJobRecord(
                messageId: nil,
                threadId: nil,
                invisibleMessage: nil,
                isMediaMessage: true,
                removeMessageAfterSending: false,
                isHighPriority: true,
                label: "msg",
                exclusiveProcessIdentifier: nil,
                failureCount: UInt(Int.max),
                status: .unknown
            ),
            Data(base64Encoded: "eyJyZW1vdmVNZXNzYWdlQWZ0ZXJTZW5kaW5nIjpmYWxzZSwic3VwZXIiOnsiZmFpbHVyZUNvdW50Ijo5MjIzMzcyMDM2ODU0Nzc1ODA3LCJsYWJlbCI6Im1zZyIsInN0YXR1cyI6MCwidW5pcXVlSWQiOiI3NTgwQzgxMy1GNzBBLTRGQjgtQjUzRC1GQjFGRUYyQzQyNTkiLCJyZWNvcmRUeXBlIjozNX0sImlzSGlnaFByaW9yaXR5Ijp0cnVlLCJpc01lZGlhTWVzc2FnZSI6dHJ1ZX0=")!
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

extension SubscriptionReceiptCredentialRedemptionJobRecord: ValidatableModel {

    static let constants: [(SubscriptionReceiptCredentialRedemptionJobRecord, base64JsonData: Data)] = [
        (
            SubscriptionReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "bank",
                receiptCredentialRequestContext: Data(base64Encoded: "beef")!,
                receiptCredentialRequest: Data(base64Encoded: "dead")!,
                receiptCredentialPresentation: Data(base64Encoded: "bade")!,
                subscriberID: Data(base64Encoded: "feed")!,
                targetSubscriptionLevel: 12,
                priorSubscriptionLevel: 4,
                isBoost: true,
                amount: 12.5,
                currencyCode: "shoop",
                boostPaymentIntentID: "de",
                label: "whoop",
                exclusiveProcessIdentifier: "da boop",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(base64Encoded: "eyJ0YXJnZXRTdWJzY3JpcHRpb25MZXZlbCI6MTIsImN1cnJlbmN5Q29kZSI6InNob29wIiwicHJpb3JTdWJzY3JpcHRpb25MZXZlbCI6NCwiYW1vdW50IjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHakN3d2FWU1J1ZFd4czF3ME9EeEFSRWhNVUZSWVhHQmdaVmlSamJHRnpjMXRPVXk1dFlXNTBhWE56WVZ0T1V5NXVaV2RoZEdsMlpWdE9VeTVsZUhCdmJtVnVkRjVPVXk1dFlXNTBhWE56WVM1aWIxbE9VeTVzWlc1bmRHaGFUbE11WTI5dGNHRmpkSUFDVHhBUWZRQUFBQUFBQUFBQUFBQUFBQUFBQUFnVFwvXC9cL1wvXC9cL1wvXC9cL1wvOFFBUW5TR3h3ZEhsb2tZMnhoYzNOdVlXMWxXQ1JqYkdGemMyVnpYeEFhVGxORVpXTnBiV0ZzVG5WdFltVnlVR3hoWTJWb2IyeGtaWEtsSHlBaElpTmZFQnBPVTBSbFkybHRZV3hPZFcxaVpYSlFiR0ZqWldodmJHUmxjbDhRRDA1VFJHVmphVzFoYkU1MWJXSmxjbGhPVTA1MWJXSmxjbGRPVTFaaGJIVmxXRTVUVDJKcVpXTjBBQWdBRVFBYUFDUUFLUUF5QURjQVNRQk1BRkVBVXdCWEFGMEFiQUJ6QUg4QWl3Q1hBS1lBc0FDN0FMMEEwQURSQU5vQTNBRGRBT0lBN1FEMkFSTUJHUUUyQVVnQlVRRlpBQUFBQUFBQUFnRUFBQUFBQUFBQUpBQUFBQUFBQUFBQUFBQUFBQUFBQVdJPSIsInN1YnNjcmliZXJJRCI6ImZlZWQiLCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3QiOiJkZWFkIiwic3VwZXIiOnsiZmFpbHVyZUNvdW50IjowLCJsYWJlbCI6Indob29wIiwic3RhdHVzIjozLCJ1bmlxdWVJZCI6IjI0QzJGQjVCLTlGM0UtNDRFNy05RTkyLTBGQjEzNjA1Q0NDRiIsImV4Y2x1c2l2ZVByb2Nlc3NJZGVudGlmaWVyIjoiZGEgYm9vcCIsInJlY29yZFR5cGUiOjcxfSwiYm9vc3RQYXltZW50SW50ZW50SUQiOiJkZSIsInJlY2VpcHRDcmVkZW50YWlsUmVxdWVzdENvbnRleHQiOiJiZWVmIiwicmVjZWlwdENyZWRlbnRpYWxQcmVzZW50YXRpb24iOiJiYWRlIiwicGF5bWVudFByb2Nlc3NvciI6ImJhbmsiLCJpc0Jvb3N0Ijp0cnVlfQ==")!
        ),
        (
            SubscriptionReceiptCredentialRedemptionJobRecord(
                paymentProcessor: "not svb",
                receiptCredentialRequestContext: Data(base64Encoded: "feeb")!,
                receiptCredentialRequest: Data(base64Encoded: "aded")!,
                receiptCredentialPresentation: nil,
                subscriberID: Data(base64Encoded: "deef")!,
                targetSubscriptionLevel: 12,
                priorSubscriptionLevel: 4,
                isBoost: true,
                amount: nil,
                currencyCode: nil,
                boostPaymentIntentID: "na na na na na na na na na na na na na na na na na na na na",
                label: "na na na na",
                exclusiveProcessIdentifier: "batman!",
                failureCount: 0,
                status: .permanentlyFailed
            ),
            Data(base64Encoded: "eyJzdWJzY3JpYmVySUQiOiJkZWVmIiwiYm9vc3RQYXltZW50SW50ZW50SUQiOiJuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSBuYSIsInN1cGVyIjp7ImZhaWx1cmVDb3VudCI6MCwibGFiZWwiOiJuYSBuYSBuYSBuYSIsInN0YXR1cyI6MywidW5pcXVlSWQiOiIyMjc0OEU5Qi02NkY2LTRCRDYtQkNDNC0xNEJBQzlEQjI2NkUiLCJleGNsdXNpdmVQcm9jZXNzSWRlbnRpZmllciI6ImJhdG1hbiEiLCJyZWNvcmRUeXBlIjo3MX0sInJlY2VpcHRDcmVkZW50YWlsUmVxdWVzdENvbnRleHQiOiJmZWViIiwicGF5bWVudFByb2Nlc3NvciI6Im5vdCBzdmIiLCJ0YXJnZXRTdWJzY3JpcHRpb25MZXZlbCI6MTIsInByaW9yU3Vic2NyaXB0aW9uTGV2ZWwiOjQsInJlY2VpcHRDcmVkZW50YWlsUmVxdWVzdCI6ImFkZWQiLCJpc0Jvb3N0Ijp0cnVlfQ==")!
        )
    ]

    func validate(against: SubscriptionReceiptCredentialRedemptionJobRecord) throws {
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
                label: "mall",
                exclusiveProcessIdentifier: "carp",
                failureCount: 9,
                status: .ready
            ),
            Data(base64Encoded: "eyJwYXlwYWxQYXltZW50VG9rZW4iOiJmbG9ycCIsInRocmVhZElkIjoicGF1bCIsInBheW1lbnRJbnRlbnRDbGllbnRTZWNyZXQiOiJzZWNyZXQiLCJhbW91bnQiOiJZbkJzYVhOME1ERFVBUUlEQkFVR0J3cFlKSFpsY25OcGIyNVpKR0Z5WTJocGRtVnlWQ1IwYjNCWUpHOWlhbVZqZEhNU0FBR0dvRjhRRDA1VFMyVjVaV1JCY21Ob2FYWmxjdEVJQ1ZSeWIyOTBnQUdqQ3d3YVZTUnVkV3hzMXcwT0R4QVJFaE1VRlJZWEdCZ1pWaVJqYkdGemMxdE9VeTV0WVc1MGFYTnpZVnRPVXk1dVpXZGhkR2wyWlZ0T1V5NWxlSEJ2Ym1WdWRGNU9VeTV0WVc1MGFYTnpZUzVpYjFsT1V5NXNaVzVuZEdoYVRsTXVZMjl0Y0dGamRJQUNUeEFRZmdBQUFBQUFBQUFBQUFBQUFBQUFBQWdUXC9cL1wvXC9cL1wvXC9cL1wvXC84UUFRblNHeHdkSGxva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelh4QWFUbE5FWldOcGJXRnNUblZ0WW1WeVVHeGhZMlZvYjJ4a1pYS2xIeUFoSWlOZkVCcE9VMFJsWTJsdFlXeE9kVzFpWlhKUWJHRmpaV2h2YkdSbGNsOFFEMDVUUkdWamFXMWhiRTUxYldKbGNsaE9VMDUxYldKbGNsZE9VMVpoYkhWbFdFNVRUMkpxWldOMEFBZ0FFUUFhQUNRQUtRQXlBRGNBU1FCTUFGRUFVd0JYQUYwQWJBQnpBSDhBaXdDWEFLWUFzQUM3QUwwQTBBRFJBTm9BM0FEZEFPSUE3UUQyQVJNQkdRRTJBVWdCVVFGWkFBQUFBQUFBQWdFQUFBQUFBQUFBSkFBQUFBQUFBQUFBQUFBQUFBQUFBV0k9IiwicmVjZWlwdENyZWRlbnRhaWxSZXF1ZXN0IjoiZGVhZCIsInBheW1lbnRNZXRob2RJZCI6ImNhcnAiLCJtZXNzYWdlVGV4dCI6ImJsYXJwIiwicGF5cGFsUGF5ZXJJZCI6ImJvcnAiLCJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjksImxhYmVsIjoibWFsbCIsInN0YXR1cyI6MSwidW5pcXVlSWQiOiI1MTk3OEI5RC1ERDQyLTQxRjAtOTM4RC03NzU4OTAwMzBCOTUiLCJleGNsdXNpdmVQcm9jZXNzSWRlbnRpZmllciI6ImNhcnAiLCJyZWNvcmRUeXBlIjo3M30sImJvb3N0UGF5bWVudEludGVudElEIjoieWFycCIsInJlY2VpcHRDcmVkZW50YWlsUmVxdWVzdENvbnRleHQiOiJiZWVmIiwicGF5cGFsUGF5bWVudElkIjoiZ29ycCIsInBheW1lbnRQcm9jZXNzb3IiOiJtb25leSIsImN1cnJlbmN5Q29kZSI6Inpob29wIn0=")!
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
                label: "mall",
                exclusiveProcessIdentifier: "carp",
                failureCount: 9,
                status: .ready
            ),
            Data(base64Encoded: "eyJhbW91bnQiOiJZbkJzYVhOME1ERFVBUUlEQkFVR0J3cFlKSFpsY25OcGIyNVpKR0Z5WTJocGRtVnlWQ1IwYjNCWUpHOWlhbVZqZEhNU0FBR0dvRjhRRDA1VFMyVjVaV1JCY21Ob2FYWmxjdEVJQ1ZSeWIyOTBnQUdqQ3d3YVZTUnVkV3hzMXcwT0R4QVJFaE1VRlJZWEdCZ1pWaVJqYkdGemMxdE9VeTV0WVc1MGFYTnpZVnRPVXk1dVpXZGhkR2wyWlZ0T1V5NWxlSEJ2Ym1WdWRGNU9VeTV0WVc1MGFYTnpZUzVpYjFsT1V5NXNaVzVuZEdoYVRsTXVZMjl0Y0dGamRJQUNUeEFRZmdBQUFBQUFBQUFBQUFBQUFBQUFBQWdUXC9cL1wvXC9cL1wvXC9cL1wvXC84UUFRblNHeHdkSGxva1kyeGhjM051WVcxbFdDUmpiR0Z6YzJWelh4QWFUbE5FWldOcGJXRnNUblZ0WW1WeVVHeGhZMlZvYjJ4a1pYS2xIeUFoSWlOZkVCcE9VMFJsWTJsdFlXeE9kVzFpWlhKUWJHRmpaV2h2YkdSbGNsOFFEMDVUUkdWamFXMWhiRTUxYldKbGNsaE9VMDUxYldKbGNsZE9VMVpoYkhWbFdFNVRUMkpxWldOMEFBZ0FFUUFhQUNRQUtRQXlBRGNBU1FCTUFGRUFVd0JYQUYwQWJBQnpBSDhBaXdDWEFLWUFzQUM3QUwwQTBBRFJBTm9BM0FEZEFPSUE3UUQyQVJNQkdRRTJBVWdCVVFGWkFBQUFBQUFBQWdFQUFBQUFBQUFBSkFBQUFBQUFBQUFBQUFBQUFBQUFBV0k9Iiwic3VwZXIiOnsiZmFpbHVyZUNvdW50Ijo5LCJsYWJlbCI6Im1hbGwiLCJzdGF0dXMiOjEsInVuaXF1ZUlkIjoiRTNFNjU0RUUtNUNDQy00MUU4LTlEOEYtMDE0QUJBRTMxQ0UxIiwiZXhjbHVzaXZlUHJvY2Vzc0lkZW50aWZpZXIiOiJjYXJwIiwicmVjb3JkVHlwZSI6NzN9LCJyZWNlaXB0Q3JlZGVudGFpbFJlcXVlc3RDb250ZXh0IjoiYmVlZiIsInBheW1lbnRQcm9jZXNzb3IiOiJtb25leSIsImN1cnJlbmN5Q29kZSI6Inpob29wIiwibWVzc2FnZVRleHQiOiJibGFycCIsInJlY2VpcHRDcmVkZW50YWlsUmVxdWVzdCI6ImRlYWQiLCJ0aHJlYWRJZCI6InBhdWwifQ==")!
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
                label: "is",
                exclusiveProcessIdentifier: "the way",
                failureCount: 14,
                status: .ready
            ),
            Data(base64Encoded: "eyJzdXBlciI6eyJmYWlsdXJlQ291bnQiOjE0LCJsYWJlbCI6ImlzIiwic3RhdHVzIjoxLCJ1bmlxdWVJZCI6IjczMkVFMTBFLTcyNzctNEVFOC04Mzc5LUNFMEJGNzcyRkE0NCIsImV4Y2x1c2l2ZVByb2Nlc3NJZGVudGlmaWVyIjoidGhlIHdheSIsInJlY29yZFR5cGUiOjUyfSwiY29udGFjdFRocmVhZElkIjoidGhpcyJ9")!
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
