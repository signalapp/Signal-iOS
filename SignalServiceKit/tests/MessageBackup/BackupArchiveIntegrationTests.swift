//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class BackupArchiveIntegrationTests: XCTestCase {
    override func setUp() {
        /// By default, we cap test runs to 60s in CI. This test might run
        /// longer, since we have very many integration test cases, so this
        /// extends the time allowance specifically for this test.
        ///
        /// As an alternative, we could avoid running all the integration test
        /// cases in one giant test. For example, in Swift Testing we can
        /// "parameterize" tests, for example parameterizing over the list of
        /// integration test cases, such that there's one "test" per integration
        /// test case. I tried that, but unfortunately at the time of writing
        /// Xcode struggles mightily with highly parameterized tests; the tests
        /// ran very slowly, and Xcode itself beach-balled.
        ///
        /// In the future, if Xcode supports this better, we can move this test
        /// to use Swift Testing and parameterization.
        ///
        /// - SeeAlso
        /// The `-test-timeouts-enabled`, `-default-test-execution-time-allowance`,
        /// and `-default-test-execution-time-allowance` command-line arguments
        /// passed during CI.
        executionTimeAllowance = 300

        DDLog.add(DDTTYLogger.sharedInstance!)
    }

    // MARK: -

    /// Describes what output to log if LibSignal reports a test failure.
    private enum LibSignalComparisonFailureLogOutput {
        /// Log the full backup JSONs returned by LibSignal, for external
        /// analysis via `parse-libsignal-comparator-failure.py`.
        case fullLibSignalJSON

        /// Log a minimal diff of the backup JSONs returned by LibSignal, for
        /// inline analysis in the Xcode logs.
        case minimalDiff
    }

    private enum WhichIntegrationTestCases {
        case all
        case specific(names: Set<String>)

        case standardFrames

        case accountData

        case adHocCall

        case chat

        case chatItem
        case chatItemContactMessage
        case chatItemExpirationTimerUpdate
        case chatItemGiftBadge
        case chatItemGroupCall
        case chatItemGroupChangeChatUpdate
        case chatItemGroupChangeChatMultipleUpdate
        case chatItemIndividualCall
        case chatItemLearnedProfile
        case chatItemPaymentNotification
        case chatItemProfileChange
        case chatItemRemoteDeleteTombstone
        case chatItemSessionSwitchover
        case chatItemSimpleUpdates
        case chatItemStandardMessageFormatted
        case chatItemStandardMessageLinkPreview
        case chatItemStandardMessageLongText
        case chatItemStandardMessageSms
        case chatItemStandardMessageSpecialAttachments
        case chatItemStandardMessageStandardAttachments
        case chatItemStandardMessageTextOnly
        case chatItemStandardMessageWithEdits
        case chatItemStandardMessageWithQuote
        case chatItemStickerMessage
        case chatItemThreadMerge
        case chatItemViewOnceMessage
        case chatItemDirectStoryReply

        case recipient
        case recipientCallLink
        case recipientContact
        case recipientDistributionList
        case recipientGroup

        case stickerPack
    }

    /// The preferred log output for test failures.
    ///
    /// Set by default to `.minimalDiff` to reduce log noise in automated test
    /// runs. Toggle to `.fullLibSignalJSON` if desired during local
    /// development, for more thorough inspection of the failure case.
    private let preferredFailureLogOutput: LibSignalComparisonFailureLogOutput = .minimalDiff

    /// Specifies which integration test cases to run.
    ///
    /// Set by default to `.all`. May be toggled to a subset of tests during
    /// local development for debugging purposes, but should never be committed
    /// to `main` as anything other than `.all`.
    private let whichIntegrationTestCases: WhichIntegrationTestCases = .all

    // MARK: -

    /// Performs a round-trip import/export test on all `.binproto` integration
    /// test cases.
    func testIntegrationTestCases() async throws {
        let binProtoFileUrls: [URL] = {
            let allBinprotoUrls = Bundle(for: type(of: self)).urls(
                forResourcesWithExtension: "binproto",
                subdirectory: nil
            ) ?? []

            return allBinprotoUrls.filter { binprotoUrl in
                let binprotoName = binprotoUrl
                    .lastPathComponent
                    .filenameWithoutExtension

                switch whichIntegrationTestCases {
                case .all:
                    return true
                case .specific(let names):
                    return names.contains(binprotoName)
                case .standardFrames:
                    return binprotoName.contains("standard_frames")
                case .accountData:
                    return binprotoName.contains("account_data_")
                case .adHocCall:
                    return binprotoName.contains("ad_hoc_call_")
                case .chat:
                    return binprotoName.contains("chat_")
                case .chatItem:
                    return binprotoName.contains("chat_item_")
                case .chatItemContactMessage:
                    return binprotoName.contains("chat_item_contact_message_")
                case .chatItemExpirationTimerUpdate:
                    return binprotoName.contains("chat_item_expiration_timer_update_")
                case .chatItemGiftBadge:
                    return binprotoName.contains("chat_item_gift_badge_")
                case .chatItemGroupCall:
                    return binprotoName.contains("chat_item_group_call_update_")
                case .chatItemGroupChangeChatUpdate:
                    return binprotoName.contains("chat_item_group_change_chat_update_")
                case .chatItemGroupChangeChatMultipleUpdate:
                    return binprotoName.contains("chat_item_group_change_chat_multiple_update_")
                case .chatItemIndividualCall:
                    return binprotoName.contains("chat_item_individual_call_update_")
                case .chatItemLearnedProfile:
                    return binprotoName.contains("chat_item_learned_profile_update_")
                case .chatItemPaymentNotification:
                    return binprotoName.contains("chat_item_payment_notification_")
                case .chatItemProfileChange:
                    return binprotoName.contains("chat_item_profile_change_")
                case .chatItemRemoteDeleteTombstone:
                    return binprotoName.contains("chat_item_remote_delete_")
                case .chatItemSessionSwitchover:
                    return binprotoName.contains("chat_item_session_switchover_update_")
                case .chatItemSimpleUpdates:
                    return binprotoName.contains("chat_item_simple_updates_")
                case .chatItemStandardMessageFormatted:
                    return binprotoName.contains("chat_item_standard_message_formatted_")
                case .chatItemStandardMessageLinkPreview:
                    return binprotoName.contains("chat_item_standard_message_with_link_preview_")
                case .chatItemStandardMessageLongText:
                    return binprotoName.contains("chat_item_standard_message_long_text_")
                case .chatItemStandardMessageSms:
                    return binprotoName.contains("chat_item_standard_message_sms_")
                case .chatItemStandardMessageSpecialAttachments:
                    return binprotoName.contains("chat_item_standard_message_special_attachments_")
                case .chatItemStandardMessageStandardAttachments:
                    return binprotoName.contains("chat_item_standard_message_standard_attachments_")
                case .chatItemStandardMessageTextOnly:
                    return binprotoName.contains("chat_item_standard_message_text_only_")
                case .chatItemStandardMessageWithEdits:
                    return binprotoName.contains("chat_item_standard_message_with_edits_")
                case .chatItemStandardMessageWithQuote:
                    return binprotoName.contains("chat_item_standard_message_with_quote_")
                case .chatItemStickerMessage:
                    return binprotoName.contains("chat_item_sticker_message_")
                case .chatItemThreadMerge:
                    return binprotoName.contains("chat_item_thread_merge_")
                case .chatItemViewOnceMessage:
                    return binprotoName.contains("chat_item_view_once_")
                case .chatItemDirectStoryReply:
                    return binprotoName.contains("chat_item_direct_story_reply_")
                case .recipient:
                    return binprotoName.contains("recipient_")
                case .recipientCallLink:
                    return binprotoName.contains("recipient_call_link_")
                case .recipientContact:
                    return binprotoName.contains("recipient_contacts_")
                case .recipientDistributionList:
                    return binprotoName.contains("recipient_distribution_list_")
                case .recipientGroup:
                    return binprotoName.contains("recipient_groups_")
                case .stickerPack:
                    return binprotoName.contains("sticker_pack_")
                }
            }
        }()

        guard binProtoFileUrls.count > 0 else {
            XCTFail("Failed to find binprotos in test bundle!")
            return
        }

        for binprotoFileUrl in binProtoFileUrls {
            let filename = binprotoFileUrl
                .lastPathComponent
                .filenameWithoutExtension

            /// Separate the `Logger` and `XCTFail` steps. We want the test to
            /// fail, but `XCTFail` is slow to get its output into the console,
            /// so we'll log the interesting failure message separately so it's
            /// sequential with whatever else is being logged (such as the next
            /// test starting).
            func logFailure(_ message: String) {
                Logger.error(message)
                XCTFail(filename)
            }

            do {
                Logger.info("""


                [TestCase] Running test case: \(filename)

                """)

                try await runRoundTripTest(
                    testCaseFileUrl: binprotoFileUrl,
                    failureLogOutput: preferredFailureLogOutput
                )
            } catch TestError.failure(let message) {
                logFailure("""

                ------------

                Test case failed: \(filename)!

                \(message)

                ------------
                """)
            } catch let error {
                logFailure("""

                ------------

                Test case failed with unexpected error: \(filename)!

                \(error)

                ------------
                """)
            }
        }

        /// Ensure we write all log output before the test finishes.
        Logger.flush()
    }

    // MARK: -

    private enum TestError: Error {
        case failure(String)
    }

    private var deps: DependenciesBridge { .shared }

    /// Runs a round-trip import/export test for the given `.binproto` file.
    ///
    /// The round-trip test imports the given `.binproto` into an empty app,
    /// then exports the app's state into another `.binproto`. The
    /// originally-imported and recently-exported `.binprotos` are then compared
    /// by LibSignal. They should be equivalent; any disparity indicates that
    /// some data was dropped or modified as part of the import/export process,
    /// which should be idempotent.
    @MainActor
    private func runRoundTripTest(
        testCaseFileUrl: URL,
        failureLogOutput: LibSignalComparisonFailureLogOutput
    ) async throws {

        /// Backup files hardcode timestamps, some of which are interpreted
        /// relative to "now". For example, "deleted" story distribution lists
        /// are marked as deleted for a period of time before being actually
        /// deleted; when these frames are restored from a Backup, their
        /// deletion timestamp is compared to "now" to determine if they should
        /// be deleted.
        ///
        /// Consequently, in order for tests to remain stable over time we need
        /// to "anchor" them with an unchanging timestamp. To that end, we'll
        /// extract the `backupTimeMs` field from the Backup header, and use
        /// that as our "now" during import.
        let backupTimeMs = try await readBackupTimeMs(testCaseFileUrl: testCaseFileUrl)

        let oldContext = CurrentAppContext()
        await initializeApp(dateProvider: { Date(millisecondsSince1970: backupTimeMs) })
        let result = await Result {
            try await self._runRoundTripTest(
                testCaseFileUrl: testCaseFileUrl,
                backupTimeMs: backupTimeMs,
                failureLogOutput: failureLogOutput
            )
        }
        await deinitializeApp(oldContext: oldContext)
        try result.get()
    }

    private func _runRoundTripTest(
        testCaseFileUrl: URL,
        backupTimeMs: UInt64,
        failureLogOutput: LibSignalComparisonFailureLogOutput
    ) async throws {
        /// A backup doesn't contain our own local identifiers. Rather, those
        /// are determined as part of registration for a backup import, and are
        /// already-known for a backup export.
        ///
        /// Consequently, we can use any local identifiers for our test
        /// purposes without worrying about the contents of each test case's
        /// backup file.
        let localIdentifiers: LocalIdentifiers = .forUnitTests

        try await deps.backupArchiveManager.importPlaintextBackup(
            fileUrl: testCaseFileUrl,
            localIdentifiers: localIdentifiers,
            isPrimaryDevice: true,
            backupPurpose: .remoteBackup,
            progress: nil
        )

        let exportedBackupUrl = try await deps.backupArchiveManager
            .exportPlaintextBackupForTests(localIdentifiers: localIdentifiers, progress: nil)

        try compareViaLibsignal(
            sharedTestCaseBackupUrl: testCaseFileUrl,
            exportedBackupUrl: exportedBackupUrl,
            failureLogOutput: failureLogOutput
        )
    }

    /// Compare the canonical representation of the Backups at the two given
    /// file URLs, via `LibSignal`.
    ///
    /// - Throws
    /// If there are errors reading or validating either Backup, or if the
    /// Backups' canonical representations are not equal.
    private func compareViaLibsignal(
        sharedTestCaseBackupUrl: URL,
        exportedBackupUrl: URL,
        failureLogOutput: LibSignalComparisonFailureLogOutput
    ) throws {
#if targetEnvironment(simulator)
        let sharedTestCaseBackup = try ComparableBackup(url: sharedTestCaseBackupUrl)
        let exportedBackup = try ComparableBackup(url: exportedBackupUrl)

        guard sharedTestCaseBackup.unknownFields.fields.isEmpty else {
            throw TestError.failure("Unknown fields: \(sharedTestCaseBackup.unknownFields)!")
        }

        let sharedTestCaseBackupString = sharedTestCaseBackup.comparableString()
        let exportedBackupString = exportedBackup.comparableString()

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted

        if sharedTestCaseBackupString != exportedBackupString {
            switch failureLogOutput {
            case .fullLibSignalJSON:
                throw TestError.failure("""
                Copy the JSON lines below and run `pbpaste | parse-libsignal-comparator-failure.py`.

                \(sharedTestCaseBackupString.removeCharacters(characterSet: .whitespacesAndNewlines))
                \(exportedBackupString.removeCharacters(characterSet: .whitespacesAndNewlines))
                """)
            case .minimalDiff:
                let jsonStringDiff: LineByLineStringDiff = .diffing(
                    lhs: sharedTestCaseBackupString,
                    rhs: exportedBackupString
                )

                let prettyDiff = jsonStringDiff.prettyPrint(
                    lhsLabel: "testcase",
                    rhsLabel: "exported",
                    diffGroupDivider: "************"
                )

                throw TestError.failure("""
                JSON diff:

                \(prettyDiff)
                """)
            }
        }
#else
        throw XCTSkip("LibSignalClient.ComparableBackup is only available in the simulator.")
#endif
    }

    // MARK: -

    /// Read the `backupTimeMs` field from the header of the Backup file at the
    /// given local URL.
    private func readBackupTimeMs(testCaseFileUrl: URL) async throws -> UInt64 {
        let plaintextStreamProvider = BackupArchivePlaintextProtoStreamProvider()

        let stream: BackupArchiveProtoInputStream
        switch plaintextStreamProvider.openPlaintextInputFileStream(
            fileUrl: testCaseFileUrl,
            frameRestoreProgress: nil
        ) {
        case .success(let _stream, _):
            stream = _stream
        case .fileNotFound:
            throw TestError.failure("Missing test case backup file!")
        case .unableToOpenFileStream:
            throw TestError.failure("Failed to open test case backup file!")
        case .hmacValidationFailedOnEncryptedFile:
            throw TestError.failure("Impossible – this is a plaintext stream!")
        }

        let backupInfo: BackupProto_BackupInfo
        switch stream.readHeader() {
        case .success(let _backupInfo, _):
            backupInfo = _backupInfo
        case .invalidByteLengthDelimiter:
            throw TestError.failure("Invalid byte length delimiter!")
        case .emptyFinalFrame:
            throw TestError.failure("Invalid empty header frame!")
        case .protoDeserializationError(let error):
            throw TestError.failure("Proto deserialization error: \(error)!")
        }

        return backupInfo.backupTimeMs
    }

    // MARK: -

    @MainActor
    private func initializeApp(dateProvider: DateProvider?) async {
        let appReadiness = AppReadinessMock()

        /// We use crashy versions of dependencies that should never be called
        /// during backups, and no-op implementations of payments because those
        /// are bound to the SignalUI target.
        await MockSSKEnvironment.activate(
            appReadiness: appReadiness,
            callMessageHandler: CrashyMocks.MockCallMessageHandler(),
            currentCallProvider: CrashyMocks.MockCurrentCallThreadProvider(),
            notificationPresenter: CrashyMocks.MockNotificationPresenter(),
            incrementalMessageTSAttachmentMigratorFactory: NoOpIncrementalMessageTSAttachmentMigratorFactory(),
            testDependencies: AppSetup.TestDependencies(
                backupAttachmentDownloadManager: BackupAttachmentDownloadManagerMock(),
                dateProvider: dateProvider,
                networkManager: CrashyMocks.MockNetworkManager(appReadiness: appReadiness, libsignalNet: nil),
                webSocketFactory: CrashyMocks.MockWebSocketFactory()
            )
        )

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            _ = TSPrivateStoryThread.getOrCreateMyStory(transaction: tx)
        }
    }

    private func deinitializeApp(oldContext: any AppContext) async {
        await MockSSKEnvironment.deactivateAsync(oldContext: oldContext)
    }
}

// MARK: -

#if targetEnvironment(simulator)
private extension LibSignalClient.ComparableBackup {
    convenience init(url: URL) throws {
        let fileHandle = try FileHandle(forReadingFrom: url)
        let fileLength = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        try self.init(
            purpose: .remoteBackup,
            length: fileLength,
            stream: fileHandle
        )
    }
}
#endif

// MARK: - CrashyMocks

private func failTest<T>(
    _ type: T.Type,
    _ function: StaticString = #function
) -> Never {
    let message = "Unexpectedly called \(type)#\(function)!"
    XCTFail(message)
    owsFail(message)
}

/// As a rule, integration tests for message backup should not mock out their
/// dependencies as their goal is to validate how the real, production app will
/// behave with respect to Backups.
///
/// These mocks are the exceptions to that rule, and encompass managers that
/// should never be invoked during Backup import or export.
private enum CrashyMocks {
    final class MockNetworkManager: NetworkManager {
        override func asyncRequest(_ request: TSRequest, canUseWebSocket: Bool = true, retryPolicy: RetryPolicy = .dont) async throws -> any HTTPResponse { failTest(Self.self) }
        override func makePromise(request: TSRequest, canUseWebSocket: Bool = true) -> Promise<any HTTPResponse> { failTest(Self.self) }
    }

    final class MockWebSocketFactory: WebSocketFactory {
        var canBuildWebSocket: Bool { failTest(Self.self) }
        func buildSocket(request: WebSocketRequest, callbackScheduler: any Scheduler) -> (any SSKWebSocket)? { failTest(Self.self) }
    }

    final class MockCallMessageHandler: CallMessageHandler {
        func receivedEnvelope(_ envelope: SSKProtoEnvelope, callEnvelope: CallEnvelopeType, from caller: (aci: Aci, deviceId: DeviceId), toLocalIdentity localIdentity: OWSIdentity, plaintextData: Data, wasReceivedByUD: Bool, sentAtTimestamp: UInt64, serverReceivedTimestamp: UInt64, serverDeliveryTimestamp: UInt64, tx: DBWriteTransaction) { failTest(Self.self) }
        func receivedGroupCallUpdateMessage(_ updateMessage: SSKProtoDataMessageGroupCallUpdate, forGroupId groupId: GroupIdentifier, serverReceivedTimestamp: UInt64) async { failTest(Self.self) }
    }

    final class MockCurrentCallThreadProvider: CurrentCallProvider {
        var hasCurrentCall: Bool { failTest(Self.self) }
        var currentGroupThreadCallGroupId: GroupIdentifier? { failTest(Self.self) }
    }

    final class MockNotificationPresenter: NotificationPresenter {
        func registerNotificationSettings() async { failTest(Self.self) }
        func notifyUser(forIncomingMessage: TSIncomingMessage, thread: TSThread, transaction: DBWriteTransaction) { failTest(Self.self) }
        func notifyUser(forIncomingMessage: TSIncomingMessage, editTarget: TSIncomingMessage, thread: TSThread, transaction: DBWriteTransaction) { failTest(Self.self) }
        func notifyUser(forReaction: OWSReaction, onOutgoingMessage: TSOutgoingMessage, thread: TSThread, transaction: DBWriteTransaction) { failTest(Self.self) }
        func notifyUser(forErrorMessage: TSErrorMessage, thread: TSThread, transaction: DBWriteTransaction) { failTest(Self.self) }
        func notifyUser(forTSMessage: TSMessage, thread: TSThread, wantsSound: Bool, transaction: DBWriteTransaction) { failTest(Self.self) }
        func notifyUser(forPreviewableInteraction: any TSInteraction & OWSPreviewText, thread: TSThread, wantsSound: Bool, transaction: DBWriteTransaction) { failTest(Self.self) }
        func notifyTestPopulation(ofErrorMessage errorString: String) { failTest(Self.self) }
        func notifyUser(forFailedStorySend: StoryMessage, to: TSThread, transaction: DBWriteTransaction) { failTest(Self.self) }
        func notifyUserOfFailedSend(inThread thread: TSThread) { failTest(Self.self) }
        func notifyUserOfMissedCall(notificationInfo: CallNotificationInfo, offerMediaType: TSRecentCallOfferType, sentAt timestamp: Date, tx: DBReadTransaction) { failTest(Self.self) }
        func notifyUserOfMissedCallBecauseOfNewIdentity(notificationInfo: CallNotificationInfo, tx: DBWriteTransaction) { failTest(Self.self) }
        func notifyUserOfMissedCallBecauseOfNoLongerVerifiedIdentity(notificationInfo: CallNotificationInfo, tx: DBWriteTransaction) { failTest(Self.self) }
        func notifyForGroupCallSafetyNumberChange(callTitle: String, threadUniqueId: String?, roomId: Data?, presentAtJoin: Bool) { failTest(Self.self) }
        func scheduleNotifyForNewLinkedDevice(deviceLinkTimestamp: Date) { failTest(Self.self) }
        func notifyUserToRelaunchAfterTransfer(completion: @escaping () -> Void) { failTest(Self.self) }
        func notifyUserOfDeregistration(tx: DBWriteTransaction) { failTest(Self.self) }
        func clearAllNotifications() { failTest(Self.self) }
        func clearAllNotificationsExceptNewLinkedDevices() { failTest(Self.self) }
        static func clearAllNotificationsExceptNewLinkedDevices() { failTest(Self.self) }
        func clearDeliveredNewLinkedDevicesNotifications() { failTest(Self.self) }
        func cancelNotifications(threadId: String) { failTest(Self.self) }
        func cancelNotifications(messageIds: [String]) { failTest(Self.self) }
        func cancelNotifications(reactionId: String) { failTest(Self.self) }
        func cancelNotificationsForMissedCalls(threadUniqueId: String) { failTest(Self.self) }
        func cancelNotifications(for storyMessage: StoryMessage) { failTest(Self.self) }
    }
}
