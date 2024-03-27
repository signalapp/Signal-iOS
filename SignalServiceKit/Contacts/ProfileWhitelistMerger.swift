//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class ProfileWhitelistMerger: RecipientMergeObserver {
    private let profileManager: ProfileManager

    init(profileManager: ProfileManager) {
        self.profileManager = profileManager
    }

    func willBreakAssociation(for recipient: SignalRecipient, mightReplaceNonnilPhoneNumber: Bool, tx: DBWriteTransaction) {
        let tx = SDSDB.shimOnlyBridge(tx)
        profileManager.normalizeRecipientInProfileWhitelist(recipient, tx: tx)
    }

    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction) {
        if mergedRecipient.isLocalRecipient {
            return
        }
        let tx = SDSDB.shimOnlyBridge(tx)
        profileManager.normalizeRecipientInProfileWhitelist(mergedRecipient.newRecipient, tx: tx)
    }
}
