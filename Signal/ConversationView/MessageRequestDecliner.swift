//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

enum MessageRequestDecliner {
    @MainActor
    static func declineMessageRequest(
        inThread thread: TSThread,
        responseType: OutgoingMessageRequestResponseSyncMessage.ResponseType,
    ) {
        let blockingManager = SSKEnvironment.shared.blockingManagerRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let deleteManager = DependenciesBridge.shared.threadSoftDeleteManager
        let syncManager = SSKEnvironment.shared.syncManagerRef

        // Leave the group if we're going to block it or delete it. (If we're only
        // reporting spam without blocking it, we remain a member of the group.)
        let shouldLeaveGroup = responseType.shouldBlockThread || responseType.shouldDeleteThread

        databaseStorage.write { tx in
            syncManager.sendMessageRequestResponseSyncMessage(
                thread: thread,
                responseType: responseType,
                transaction: tx,
            )
            if responseType.shouldBlockThread {
                blockingManager.addBlockedThread(
                    thread,
                    blockMode: .local,
                    transaction: tx,
                )
            }
            if responseType.shouldReportSpam {
                let spamReport = ReportSpamUIUtils.insertSpamReportMessage(in: thread, tx: tx)
                // We don't wait for this because it's best effort.
                Task {
                    _ = try? await spamReport?.submit(using: SSKEnvironment.shared.networkManagerRef)
                }
            }
            if shouldLeaveGroup, let thread = thread as? TSGroupThread, thread.groupModel.groupMembership.isLocalUserFullOrInvitedMember {
                // We don't wait for this because it's durably enqeueued and may take up to
                // 24 hours to complete.
                _ = GroupManager.localLeaveGroupOrDeclineInvite(
                    groupThread: thread,
                    waitForMessageProcessing: true,
                    tx: tx,
                )
            }
            if responseType.shouldDeleteThread {
                deleteManager.softDelete(
                    threads: [thread],
                    // We're already sending a sync message about this above!
                    sendDeleteForMeSyncMessage: false,
                    updateStorageService: true,
                    tx: tx,
                )
            }
        }
    }
}
