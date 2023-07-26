//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension GroupManager {
    /// Inserts an info message into the given thread describing how the thread
    /// has been updated, given before/after models for the thread.
    ///
    /// - Parameter newlyLearnedPniToAciAssociations
    /// Associations between PNIs and ACIs that were learned as a result of this
    /// group update.
    public static func insertGroupUpdateInfoMessage(
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken,
        newlyLearnedPniToAciAssociations: [UntypedServiceId: UntypedServiceId],
        groupUpdateSourceAddress: SignalServiceAddress?,
        transaction: SDSAnyWriteTransaction
    ) {
        guard
            let localIdentifiers = tsAccountManager.localIdentifiers(transaction: transaction)
        else {
            owsFailDebug("Missing local identifiers, skipping info message!")
            return
        }

        DependenciesBridge.shared.groupUpdateInfoMessageInserter.insertGroupUpdateInfoMessage(
            localIdentifiers: localIdentifiers,
            groupThread: groupThread,
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            transaction: transaction.asV2Write
        )
    }
}
