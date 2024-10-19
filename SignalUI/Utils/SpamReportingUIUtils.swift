//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
import LibSignalClient

public struct ReportSpamUIUtils {
    public typealias Completion = (Bool) -> Void

    public static func showReportSpamActionSheet(
        _ thread: TSThread,
        isBlocked: Bool,
        from viewController: UIViewController,
        completion: Completion?
    ) {
        let actionSheet = createReportSpamActionSheet(for: thread, isBlocked: isBlocked)
        viewController.presentActionSheet(actionSheet)
    }

    public static func createReportSpamActionSheet(for thread: TSThread, isBlocked: Bool) -> ActionSheetController {
        let actionSheetTitle = OWSLocalizedString(
            "MESSAGE_REQUEST_REPORT_CONVERSATION_TITLE",
            comment: "Action sheet title to confirm reporting a conversation as spam via a message request."
        )
        let actionSheetMessage = OWSLocalizedString(
            "MESSAGE_REQUEST_REPORT_CONVERSATION_MESSAGE",
            comment: "Action sheet message to confirm reporting a conversation as spam via a message request."
        )

        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "MESSAGE_REQUEST_REPORT_SPAM_ACTION",
                comment: "Action sheet action to confirm reporting a conversation as spam via a message request."
            ),
            handler: { _ in
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    Self.reportSpam(in: thread, tx: tx)
                }
            })
        )
        if !isBlocked {
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "MESSAGE_REQUEST_BLOCK_AND_REPORT_SPAM_ACTION",
                    comment: "Action sheet action to confirm blocking and reporting spam for a thread via a message request."
                ),
                handler: { _ in
                    SSKEnvironment.shared.databaseStorageRef.write { tx in
                        Self.blockAndReport(in: thread, tx: tx)
                    }
                })
            )
        }
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel))
        return actionSheet
    }

    public static func blockAndReport(in thread: TSThread, tx: SDSAnyWriteTransaction) {
        SSKEnvironment.shared.blockingManagerRef.addBlockedThread(
            thread,
            blockMode: .localShouldNotLeaveGroups,
            transaction: tx
        )

        Self.reportSpam(in: thread, tx: tx)

        SSKEnvironment.shared.syncManagerRef.sendMessageRequestResponseSyncMessage(
            thread: thread,
            responseType: .blockAndSpam
        )
    }

    public static func report(in thread: TSThread, tx: SDSAnyWriteTransaction) {
        Self.reportSpam(in: thread, tx: tx)

        SSKEnvironment.shared.syncManagerRef.sendMessageRequestResponseSyncMessage(
            thread: thread,
            responseType: .blockAndSpam
        )
    }

    private static func reportSpam(in thread: TSThread, tx: SDSAnyWriteTransaction) {
        var aci: Aci?
        var isGroup = false
        if let contactThread = thread as? TSContactThread {
            aci = contactThread.contactAddress.serviceId as? Aci
        } else if let groupThread = thread as? TSGroupThread {
            isGroup = true
            let accountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = accountManager.localIdentifiers(tx: tx.asV2Read) else {
                return owsFailDebug("Missing local identifiers")
            }
            let groupMembership = groupThread.groupModel.groupMembership
            if let invitedAtServiceId = groupMembership.localUserInvitedAtServiceId(localIdentifiers: localIdentifiers) {
                aci = groupMembership.addedByAci(forInvitedMember: invitedAtServiceId)
            }
        } else {
            return owsFailDebug("Unexpected thread type for reporting spam \(type(of: thread))")
        }

        guard let aci else {
            return owsFailDebug("Missing ACI for reporting spam")
        }

        let infoMessage = TSInfoMessage(thread: thread, messageType: .reportedSpam)
        infoMessage.anyInsert(transaction: tx)

        // We only report a selection of the N most recent messages
        // in the conversation.
        let maxMessagesToReport = 3

        var guidsToReport = Set<String>()
        do {
            if isGroup {
                guard let localIdentifiers: LocalIdentifiers =
                        DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                    owsFailDebug("Unable to find local identifiers")
                    return
                }
                try InteractionFinder(
                    threadUniqueId: thread.uniqueId
                ).enumerateRecentGroupUpdateMessages(
                    transaction: tx
                ) { infoMessage, stop in
                    guard let groupUpdateItems = infoMessage.computedGroupUpdateItems(localIdentifiers: localIdentifiers, tx: tx) else {
                        return
                    }

                    for item in groupUpdateItems {
                        if
                            let serverGuid = infoMessage.serverGuid,
                            let updaterAci = item.aciForSpamReporting,
                            updaterAci.wrappedValue == aci
                        {
                            guidsToReport.insert(serverGuid)
                        }
                    }
                    guard guidsToReport.count < maxMessagesToReport else {
                        stop.pointee = true
                        return
                    }
                }

            } else {
                try InteractionFinder(
                    threadUniqueId: thread.uniqueId
                ).enumerateInteractionsForConversationView(
                    rowIdFilter: .newest,
                    tx: tx
                ) { interaction -> Bool in
                    guard let incomingMessage = interaction as? TSIncomingMessage else { return true }
                    if let serverGuid = incomingMessage.serverGuid {
                        guidsToReport.insert(serverGuid)
                    }
                    if guidsToReport.count < maxMessagesToReport {
                        return true
                    }
                    return false
                }
            }
        } catch {
            owsFailDebug("Failed to lookup guids to report \(error)")
        }

        var reportingToken: SpamReportingToken?
        do {
            reportingToken = try SpamReportingTokenRecord.reportingToken(
                for: aci,
                database: tx.unwrapGrdbRead.database
            )
        } catch {
            owsFailBeta("Failed to look up spam reporting token. Continuing on, as the parameter is optional. Error: \(error)")
        }

        guard !guidsToReport.isEmpty else {
            Logger.warn("No messages with serverGuids to report.")
            return
        }

        Logger.info(
            "Reporting \(guidsToReport.count) message(s) from \(aci) as spam. We \(reportingToken == nil ? "do not have" : "have") a reporting token"
        )

        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for guid in guidsToReport {
                        let request = OWSRequestFactory.reportSpam(from: aci, withServerGuid: guid, reportingToken: reportingToken)
                        group.addTask {
                            _ = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
                        }
                    }
                    for try await _ in group {}
                }
                Logger.info("Successfully reported \(guidsToReport.count) message(s) from \(aci) as spam.")
            } catch {
                owsFailDebug("Failed to report message(s) from \(aci) as spam with error: \(error)")
            }
        }
    }
}
