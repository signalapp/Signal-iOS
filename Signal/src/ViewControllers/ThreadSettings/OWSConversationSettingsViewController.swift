//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension OWSConversationSettingsViewController {

    // MARK: - Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    // MARK: -

    @objc
    func updateDisappearingMessagesConfigurationObjc(_ dmConfiguration: OWSDisappearingMessagesConfiguration,
                                                     thread: TSThread) {
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.updateDisappearingMessagesConfiguration(dmConfiguration,
                                                                                                         thread: thread)
        },
                                                        completion: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        })
    }
}

// MARK: -

extension OWSConversationSettingsViewController {
    func updateDisappearingMessagesConfiguration(_ dmConfiguration: OWSDisappearingMessagesConfiguration,
                                                 thread: TSThread) -> Promise<Void> {

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: thread,
                                                         description: self.logTag)
        }.map(on: .global()) {
            // We're sending a message, so we're accepting any pending message request.
            ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
        }.then(on: .global()) {
            GroupManager.localUpdateDisappearingMessages(thread: thread,
                                                         disappearingMessageToken: dmConfiguration.asToken)
        }
    }
}
