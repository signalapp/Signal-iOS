//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public extension OWSConversationSettingsViewController {

    func updateDisappearingMessagesConfigurationObjc(_ dmConfiguration: OWSDisappearingMessagesConfiguration,
                                                     thread: TSThread) -> AnyPromise {
        return AnyPromise(GroupManager.updateDisappearingMessages(thread: thread,
                                                                  disappearingMessageToken: dmConfiguration.asToken))
    }
}
