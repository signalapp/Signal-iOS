//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension OWSConversationSettingsViewController {

    var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    @objc
    func updateDisappearingMessagesConfigurationObjc(_ dmConfiguration: OWSDisappearingMessagesConfiguration,
                                                     thread: TSThread) -> AnyPromise {
        return AnyPromise(updateDisappearingMessagesConfiguration(dmConfiguration, thread: thread))
    }

    func updateDisappearingMessagesConfiguration(_ dmConfiguration: OWSDisappearingMessagesConfiguration,
                                                 thread: TSThread) -> Promise<Void> {
        return DispatchQueue.global().async(.promise) {
            // We're sending a message, so we're accepting any pending message request.
            ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
        }.then {
            GroupManager.localUpdateDisappearingMessages(thread: thread,
                                                         disappearingMessageToken: dmConfiguration.asToken)
        }
    }
}
