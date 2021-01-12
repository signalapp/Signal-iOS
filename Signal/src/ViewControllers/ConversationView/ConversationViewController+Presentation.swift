//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ConversationViewPresentation: NSObject {
    let action: ConversationViewAction
    let focusMessageId: String?

    @objc
    public required init(action: ConversationViewAction = .none,
                         focusMessageId: String? = nil) {
        self.action = action
        self.focusMessageId = focusMessageId

        super.init()
    }
}
