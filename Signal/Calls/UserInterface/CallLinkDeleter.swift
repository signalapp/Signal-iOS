//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit
import SignalUI

enum CallLinkDeleter {
    @MainActor
    static func promptToDelete(fromViewController viewController: UIViewController, proceedAction: @escaping @MainActor () async -> Void) {
        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "CALL_LINK_DELETE_TITLE",
                comment: "Title shown in a confirmation popup asking the user if they want to delete a call link."
            ),
            message: OWSLocalizedString(
                "CALL_LINK_DELETE_MESSAGE",
                comment: "Text shown in a confirmation popup asking the user if they want to delete a call link."
            ),
            proceedTitle: CallsListViewController.Strings.deleteCallActionTitle,
            proceedStyle: .destructive,
            proceedAction: { _ in Task { await proceedAction() } },
            fromViewController: viewController
        )
    }

    static func deleteCallLink(
        stateUpdater: CallLinkStateUpdater,
        storageServiceManager: any StorageServiceManager,
        rootKey: CallLinkRootKey,
        adminPasskey: Data
    ) async throws {
        try await stateUpdater.deleteCallLink(rootKey: rootKey, adminPasskey: adminPasskey)
        storageServiceManager.recordPendingUpdates(callLinkRootKeys: [rootKey])
    }

    static var successText: String {
        return OWSLocalizedString(
            "CALL_LINK_DELETED",
            comment: "Text shown in an overlay toast after a call link is successfully deleted."
        )
    }

    static var failureText: String {
        return OWSLocalizedString(
            "CALL_LINK_DELETE_FAILED",
            comment: "Text shown in an overlay toast trying and failing to delete a call link."
        )
    }
}
